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
            def batched(options = {}, &block)
              batch_name = Resque::Plugins::BatchedLogging.sanitize_batch_name(options[:batch_name] || self.to_s)
              raise Resque::Plugins::BatchedLogging::BatchExists.new("Batch name '#{batch_name}' exists already") if Resque.redis.get("#{batch_name}:jobcount")

              job_count = 0
              if params_list = options[:paramaters]
                job_count = params_list.size
                params_list.each do |params|
                  self.enqueue(self, *(params + [{:batched_log_group => batch_name}]))
                end
              elsif block_given?
                proxy_obj = BatchLoggerProxy.new(self, batch_name)
                proxy_obj.run(&block)
                job_count = proxy_obj.job_count
              else
                raise "Must pass parameters or a block through to a batched group of jobs"
              end
              Resque.enqueue(Resque::Plugins::BatchedLogger, batch_name) # Queue a job to proccess the log information that is stored in redis
              Resque.redis.set("#{batch_name}:jobcount", job_count)
            end

            # Plugin.around_hook for wrapping the job in logging code
            def around_perform_log_as_batched(*args)
              options = args.last
              queued_with_batching = options && options.is_a?(Hash) && options.keys.include?(:batched_log_group)
              # We are unable to remove the custom options hash that is present here, so 
              if batch_name = self.group_batched_name
                self.stop_logging_batched # We know we're logging now, so turn it back off
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

            @@group_batched_name = nil
            def group_batched_name
              @@group_batched_name
            end
            alias :logging_as_batched? :group_batched_name
            def start_logging_batched(batch)
              @@group_batched_name = batch
            end
            def stop_logging_batched
              @@group_batched_name = nil
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
          @batch_name = Resque::Plugins::BatchedLogging.sanitize_batch_name(batch_name || @job_type.to_s)
          @job_count = 0
        end
        def run(&block)
          instance_eval(&block) if block_given?
        end
        # Capture #create, and #enqueue calls that are done within the scope of a MyJob.in_batches block and enqueue the original job
        def enqueue(*args)
          arguments = args + [{:batched_log_group => @batch_name}]
          if @job_type.respond_to?(:enqueue)
            @job_type.enqueue(*arguments)
          elsif @job_type.respond_to?(:create)
            @job_type.create(*arguments)
          else
            Resque.enqueue(@job_type, *arguments)
          end
          @job_count += 1
        end
        alias :create :enqueue
      end
      
      private
      
      # No spaces in redis keys
      def self.sanitize_batch_name(name)
        name.gsub(" ", "_")
      end

    end
  end
end