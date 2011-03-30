module Resque
  module Plugins
    class BatchedLogger < Resque::Job

      require 'time'

      @queue = :batched_logger
      LOG_FILE = "log/batched_jobs.log"

      def self.perform(batch_name)
        if !batch_to_log?(batch_name)
          log = File.open(LOG_FILE, "w")
          log.puts("No jobs to log for '#{batch_name}'")
          log.close
        elsif jobs_pending?(batch_name)
          sleep 5                          # Wait 5 seconds
          Resque.enqueue(self, batch_name) # Requeue, to check again
        else
          # Start processing the logs
          # Pull in the info stored in redis
          job_stats = {
            :processing_time => 0,      :longest_processing_time => 0,
            :processed_job_count => 0,  :enqueued_job_count => Resque.redis.get("#{batch_name}:jobcount"),
            :start_time => nil,         :finish_time => nil
          }
          Resque.redis.del("#{batch_name}:jobcount") # Stop any other logging processes picking up the same job
          # lpop pops the first element off the list in redis
          while job = Resque.redis.lpop("batch_stats:#{batch_name}")
            job = decode_job(job) # Decode from string format
            # job => [run_time, start_time, end_time]
            job_stats[:processing_time] += job[0]                                                           # run_time
            job_stats[:longest_processing_time] = job[0] if job[0] > job_stats[:longest_processing_time]
            job_stats[:start_time] ||= job[1]                                                               # start_time
            job_stats[:finish_time] ||= job[2]
            job_stats[:finish_time] = job[2] if job[2] > job_stats[:finish_time]                            # end_time
            job_stats[:processed_job_count] += 1
          end
          Resque.redis.del("batch_stats:#{batch_name}") # Cleanup the array of stats we've just processed (it should be empty now)

          job_stats[:total_time] = job_stats[:finish_time] - job_stats[:start_time]

          # Aggregate stats
          job_stats[:average_time] = job_stats[:total_time] / job_stats[:processed_job_count].to_f
          FileUtils.mkdir_p(File.dirname(LOG_FILE))
          log = File.open(LOG_FILE, "w")
          log.puts "==== Batched jobs '#{batch_name}' : logged at #{Time.now.to_s} ===="
          log.puts "  batch started processing at: #{job_stats[:start_time]}"
          log.puts "  batch finished processing at: #{job_stats[:finish_time]}"
          log.puts "  Total run time for batch: #{job_stats[:total_time]} seconds"

          log.puts "  Jobs Enqueued: #{job_stats[:enqueued_job_count]}"
          log.puts "  Jobs Processed: #{job_stats[:processed_job_count]}"
          log.puts "  Average time per job: #{job_stats[:average_time]} seconds"
          log.puts "  Total time spent processing jobs: #{job_stats[:processing_time]} seconds"

          log.puts "==== Batched jobs '#{batch_name}' completed at #{job_stats[:finish_time]} took #{job_stats[:total_time]} seconds ===="
          log.close
        end
      end

      private
        # It is possible that there might be more jobs processed than the number specified, in those cases we will process them all anyway
        def self.jobs_pending?(batch_name)
          jobs = Resque.redis.get("#{batch_name}:jobcount")
          jobs && Resque.redis.llen("batch_stats:#{batch_name}") < jobs.to_i
        end
        def self.batch_to_log?(batch_name)
          jobs = Resque.redis.get("#{batch_name}:jobcount")
        end

        def self.decode_job(job)
          job = JSON.parse(job)
          job[1] = Time.parse(job[1])
          job[2] = Time.parse(job[2])
          job
        end
    end
  end
end