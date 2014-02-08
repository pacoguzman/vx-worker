require 'vx/message'
require 'vx/instrumentation'

module Vx
  module Worker

    UpdateJobStatus = Struct.new(:app) do

      include Helper::Instrument

      STARTED  = 2
      FINISHED = 3
      BROKEN   = 4
      FAILED   = 5

      def call(env)

        update_status env.job, STARTED
        rs = -1
        begin
          rs = app.call env
        rescue ::Timeout::Error => e
          env.job.add_to_output("\n\nERROR: #{e.class}, #{e.message}\n")
        rescue ::Exception => e
          env.job.add_to_output("\n\nERROR: #{e.class}, #{e.message}\n")
          Vx::Instrumentation.handle_exception("worker", e, env.to_h)
        end

        msg = "\nDone. Your build exited with %s.\n"
        env.job.add_to_output(msg % rs.abs)

        case
        when rs == 0
          update_status env.job, FINISHED
        when rs > 0
          update_status env.job, BROKEN
        when rs < 0
          update_status env.job, FAILED
        end

        rs
      end

      private

        def update_status(job, status)
          instrument(
            "update_job_status",
            job.instrumentation.merge(status: status)
          )
          publish_status create_message(job, status)
        end

        def create_message(job, status)
          tm = Time.now
          Message::JobStatus.new(
            project_id: job.message.project_id,
            build_id:   job.message.build_id,
            job_id:     job.message.job_id,
            status:     status,
            tm:         tm.to_i,
          )
        end

        def publish_status(message)
          JobStatusConsumer.publish(
            message,
            headers: {
              build_id:   message.build_id,
              job_id:     message.job_id
            }
          )
        end

    end
  end
end
