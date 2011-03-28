module Resque
  module Plugins
    class Job
      # MyJob.in_batches(:batch_name => "MyCustomBatchName") do
      #   enqueue(1,2,3,{:my => :options})
      # end
      def self.in_batches(params_list = nil, options = {})
        job_count = 0
        if params_list
          job_count = params_list.size
          params_list.each do |params|
            self.enqueue(self, *(params + [{:batched => options[:batch_name] || true}]))
          end
        elsif block_given?
          proxy_obj = BatchLoggerProxy.new(self, options[:batch_name])
          yield proxy_obj
          job_count = proxy_obj.job_count
        else
          raise "Must pass parameters or a block through to a batched group of jobs"
        end
        batch = batch_name || self.to_s
        Resque::Plugins::BatchedJobLogger.create(batch) # Queue a job to proccess the log information that is stored in redis
        Resque.redis.set("#{batch}:jobcount", job_count)
      end

      # MyJob.enqueue(1,2,{:my => :options}), will be passed through as is, to the job with those parameters
      # MyJob.enqueue(1,2,{:my => :options}, {:batched => true})
      # MyJob.enqueue(1,2,{:my => :options}, {:batched => "my_custom_batch_name"})
      def perform_with_logging(*args)
        stripped_args = args.dup # In case we need to use the unmodified original arguments
        options = stripped_args.extract_options!.symbolize_keys
        if options.keys.include?(:batched)
          if options[:batched]
            batch_name = options[:batched] == true ? self.class.to_s : options[:batched] # if an explicit value of true was set, use our default name of the job class, otherwise treat the value passed as the name of the batch
            # Perform our logging
            start_time = Time.now
            runlength = Benchmark.realtime do
              perform_without_logging(*stripped_args)
            end
            end_time = Time.now
            # Store, [run_time, start_time, end_time] as an entry into redis under in an array for this specific job type & queue
            Resque.redis.lpush(batch_name, [run_time, start_time, end_time]) # Push the values onto the end of the list (will create the list if it doesn't exist)
            # End of our logging
          else
            perform_without_logging(*stripped_args) #Still strip the parameters to standard format, but don't log
          end
        else
          perform_without_logging(*args) # Send through the original, if there was no :batched option sent through
        end
      end

      # e.g. alias_method_chain :perform, :logging
      alias_method :perform_without_logging, :perform
      alias_method :perform, :perform_with_logging

      # For enabling MyJob.in_batches with block syntax
      class BatchLoggerProxy
        attr_reader :job_type, :batch_name
        attr_accessor :job_count
        def initialize(job_type, batch_name)
          @job_type = job_type
          @batch_name = batch_name
          @job_count = 0
        end
        # Capture #create, and #enqueue calls that are done within the scope of a MyJob.in_batches block and enqueue the original job
        def enqueue(*args)
          if @job_type.respond_to?(:enqueue)
            @job_type.enqueue(*(args + [{:batched => @batch_name || true}]))
          else
            @job_type.create(*(args + [{:batched => @batch_name || true}]))
          end
          @job_count += 1
        end
        alias :create :enqueue
      end

    end
  end
end