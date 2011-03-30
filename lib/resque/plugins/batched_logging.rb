module Resque
  module Plugins
    module BatchedLogging

      require 'benchmark'

      class BatchExists < StandardError; end;

      def self.included(base)
        base.class_eval do
          class << self

            # MyJob.batched(:batch_name => "MyCustomBatchName") do
            #   enqueue(1,2,3,{:my => :options})
            # end
            def batched(&block)
              batch_name = self.to_s # Group the batch of jobs by the job's class name
              raise Resque::Plugins::BatchedLogging::BatchExists.new("Batch for '#{batch_name}' exists already") if Resque.redis.get("#{batch_name}:jobcount")

              job_count = 0
              Resque.redis.set("#{batch_name}:jobcount", job_count) # Set the job count right away, because the workers will check for it's existence
              if block_given?
                proxy_obj = Resque::Plugins::BatchedLogging::BatchLoggerProxy.new(self, batch_name)
                proxy_obj.run(&block)
                job_count = proxy_obj.job_count
              else
                raise "Must pass a block through to a batched group of jobs"
              end
              Resque.enqueue(Resque::Plugins::BatchedLogger, batch_name) # Queue a job to proccess the log information that is stored in redis
              Resque.redis.set("#{batch_name}:jobcount", job_count)
            end

            # Plugin.around_hook for wrapping the job in logging code
            def around_perform_log_as_batched(*args)
              batch_name = self.to_s
              # Presence of the jobcount variable means that batched logging is enabled for this job type
              if Resque.redis.get("#{batch_name}:jobcount")
                # Perform our logging
                start_time = Time.now
                run_time = Benchmark.realtime do
                  yield
                end
                end_time = Time.now
                # Store, [run_time, start_time, end_time] as an entry into redis under in an array for this specific job type & queue
                # rpush appends to the end of a list in redis
                Resque.redis.rpush("batch_stats:#{batch_name}", [run_time, start_time, end_time].to_json) # Push the values onto the end of the list (will create the list if it doesn't exist)
                # End of our logging
              else
                yield # Just perform the standard job without benchmarking
              end
            end

          end
        end
      end

      # For enabling MyJob.in_batches with block syntax
      class BatchLoggerProxy
        attr_reader :job_type, :batch_name
        attr_accessor :job_count
        def initialize(job_type, batch_name)
          @job_type = job_type
          @batch_name = batch_name || @job_type.to_s
          @job_count = 0
        end
        def run(&block)
          instance_eval(&block) if block_given?
        end
        # Capture #create, and #enqueue calls that are done within the scope of a MyJob.in_batches block and enqueue the original job
        def enqueue(*args)
          if @job_type.respond_to?(:enqueue)
            @job_type.enqueue(*args)
          elsif @job_type.respond_to?(:create)
            @job_type.create(*args)
          else
            Resque.enqueue(@job_type, *args)
          end
          @job_count += 1
        end
        alias :create :enqueue
      end

    end
  end
end