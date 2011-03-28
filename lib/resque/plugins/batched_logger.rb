module Resque
  module Plugins
    class BatchedLogger < Resque::Job
      @queue = :batched_logger

      def self.perform(batch_name)
        unless jobs_finished?(batch_name)
          sleep 5                  # Wait 5 seconds
          self.enqueue(batch_name) # Requeue, to check again
        else
          # Pull in the info stored in redis
          job_stats = {:processing_time => 0, :longest_processing_time => nil, :job_count => Resque.redis.get("#{batch_name}:jobcount"), :start_time => nil, :finish_time => nil}
          while job = Resque.redis.lpop(batch_name)
            #job [run_time, start_time, end_time]
            job_stats[:processing_time] += job[0]                                                           # run_time
            job_stats[:longest_processing_time] = job[0] if job[0] > job_stats[:longest_processing_time]
            job_stats[:start_time] ||= job[1]                                                               # start_time
            job_stats[:finish_time] = job[2] if job[2] > job_stats[:finish_time]                            # end_time
          end
          total_time = job_stats[:finish_time] - job_stats[:start_time]

          # Aggregate stats
          job_stats[:average_time] = job_stats[:total_time] / job_stats[:job_count].to_f
          log = File.open("log/batched_jobs.log", "w")
          log.puts "==== Batched jobs '#{batch_name}' : logged at #{Time.now.to_s} ===="
          log.puts "  batch started processing at: #{job_stats[:start_time]}"
          log.puts "  batch finished processing at: #{job_stats[:finish_time]}"
          log.puts "  Total run time for batch: #{total_time} seconds"

          log.puts "  Jobs Completed: #{job_stats[:job_count]}"
          log.puts "  Average time per job: #{job_stats[:average_time]} seconds"
          log.puts "  Total time spent processing jobs: #{job_stats[:processing_time]} seconds"

          log.puts "==== Batched jobs '#{batch_name}' completed in #{total_time} seconds ===="
          log.close

          cleanup_batch(batch_name)
        end
      end

      private
        def self.jobs_finished?(batch_name)
          jobs = Resque.redis.get("#{batch_name}:jobcount")
          jobs && Resque.redis.llen(batch_name) == jobs.to_i
        end

        def self.cleanup_batch(batch_name)
          Resque.redis.del("#{batch_name}:jobcount")
        end
    end
  end
end