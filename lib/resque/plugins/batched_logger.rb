module Resque
  module Plugins
    class BatchedLogger

      require 'time'
      require 'fileutils'

      @queue = :batched_logger
      LOG_FILE = "log/batched_jobs.log"
      @@logger = nil

      # Requeue's all loggers
      def self.requeue_all
        Resque.redis.keys("*:jobcount").each do |key|
          Resque.enqueue(self, key.gsub(":jobcount", ""))
        end
      end

      def self.perform(batch_name)
        begin
          FileUtils.mkdir_p(File.dirname(LOG_FILE))
          FileUtils.touch(LOG_FILE)

          if !batch_to_log?(batch_name)
            logger.puts("No jobs to log for '#{batch_name}'")
          elsif jobs_pending?(batch_name)
            sleep 5                          # Wait 5 seconds
            Resque.enqueue(self, batch_name) # Requeue, to check again
          else
            # Start processing the logs
            # Pull in the info stored in redis
            job_stats = {
              :collective_processing_time => 0, :start_time => nil, :finish_time => nil,
              :processed_job_count => 0, :enqueued_job_count => Resque.redis.get("#{batch_name}:jobcount")
            }
            Resque.redis.del("#{batch_name}:jobcount") # Stop any other logging processes picking up the same job
            # lpop pops the first element off the list in redis
            while job = Resque.redis.lpop("batch_stats:#{batch_name}")
              job = decode_job(job) # Decode from string format, => [run_time, start_time, end_time]
              job_stats[:collective_processing_time] += job[0]
              job_stats[:start_time] = job[1] if !job_stats[:start_time] || job[1] < job_stats[:start_time]
              job_stats[:finish_time] = job[2] if !job_stats[:finish_time] || job[2] > job_stats[:finish_time]
              job_stats[:processed_job_count] += 1
            end
            Resque.redis.del("batch_stats:#{batch_name}") # Cleanup the array of stats we've just processed (it should be empty now)

            if job_stats[:processed_job_count].zero?
              log_empty_batch(batch_name)
            else
              log_stats(batch_name, job_stats)
            end
          end
        ensure
          logger.close
          @@logger = nil
        end
      end

      protected

      def self.logger
        @@logger ||= File.open(LOG_FILE, "a")
      end

      def self.log_stats(batch_name, job_stats)
        total_time = job_stats[:finish_time] - job_stats[:start_time]
        average_time = total_time / job_stats[:processed_job_count].to_f

        logger.puts "==== Batched jobs '#{batch_name}' : logged at #{Time.now} ===="
        logger.puts "  Jobs Enqueued: #{job_stats[:enqueued_job_count]}, Jobs Processed: #{job_stats[:processed_job_count]}"
        logger.puts "  Batch started: #{job_stats[:start_time]}"
        logger.puts "  Batch finished: #{job_stats[:finish_time]}"
        logger.puts "  Batch total run time: #{total_time} seconds"
        logger.puts "  Batch average per job: #{average_time} seconds"
        logger.puts "  Total time spent across all workers: #{job_stats[:collective_processing_time]} seconds"
        logger.puts "" # a new line to make things more readable
      end

      def self.log_empty_batch(batch_name)
        logger.puts "==== Batched jobs '#{batch_name}' : logged at #{Time.now} ===="
        logger.puts "  Jobs Enqueued: 0, Jobs Processed: 0"
        logger.puts "" # a new line to make things more readable
      end

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