module Resque
  module Plugins
    class BatchedLogger < Resque::Job
      @queue = :batched_logger
      
      LOG_FILE = "log/batched_jobs.log"

      def self.perform(batch_name)
        unless jobs_finished?(batch_name)
          sleep 5                  # Wait 5 seconds
          Resque.enqueue(self, batch_name) # Requeue, to check again
        else
          # Pull in the info stored in redis
          job_stats = {:processing_time => 0, :longest_processing_time => 0, :job_count => Resque.redis.get("#{batch_name}:jobcount"), :start_time => nil, :finish_time => nil}
          # lpop pops the first element off the list in redis
          while job = Resque.redis.lpop("batch_stats:#{batch_name}")
            job = decode_job(job) # Decode from string format
            # job => [run_time, start_time, end_time]
            job_stats[:processing_time] += job[0]                                                           # run_time
            job_stats[:longest_processing_time] = job[0] if job[0] > job_stats[:longest_processing_time]
            job_stats[:start_time] ||= job[1]                                                               # start_time
            job_stats[:finish_time] ||= job[2]
            job_stats[:finish_time] = job[2] if job[2] > job_stats[:finish_time]                            # end_time
          end
          job_stats[:total_time] = job_stats[:finish_time] - job_stats[:start_time]

          # Aggregate stats
          job_stats[:average_time] = job_stats[:total_time] / job_stats[:job_count].to_f
          FileUtils.mkdir_p(File.dirname(LOG_FILE))
          log = File.open(LOG_FILE, "w")
          log.puts "==== Batched jobs '#{batch_name}' : logged at #{Time.now.to_s} ===="
          log.puts "  batch started processing at: #{job_stats[:start_time]}"
          log.puts "  batch finished processing at: #{job_stats[:finish_time]}"
          log.puts "  Total run time for batch: #{job_stats[:total_time]} seconds"

          log.puts "  Jobs Completed: #{job_stats[:job_count]}"
          log.puts "  Average time per job: #{job_stats[:average_time]} seconds"
          log.puts "  Total time spent processing jobs: #{job_stats[:processing_time]} seconds"

          log.puts "==== Batched jobs '#{batch_name}' completed at #{job_stats[:finish_time]} took #{job_stats[:total_time]} seconds ===="
          log.close

          cleanup_batch(batch_name)
        end
      end

      private
        def self.jobs_finished?(batch_name)
          jobs = Resque.redis.get("#{batch_name}:jobcount")
          jobs && Resque.redis.llen("batch_stats:#{batch_name}") == jobs.to_i
        end

        def self.decode_job(job)
          job = JSON.parse(job)
          job[1] = Time.parse(job[1])
          job[2] = Time.parse(job[2])
          job
        end

        def self.cleanup_batch(batch_name)
          Resque.redis.del("#{batch_name}:jobcount")
          Resque.redis.del("batch_stats:#{batch_name}")
        end
    end
  end
end