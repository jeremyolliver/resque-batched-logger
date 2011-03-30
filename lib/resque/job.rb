module Resque
  class Job

    # Overloading the accessor for reading the job's arguments.
    # The reason for this is because the around filter in Resque::Plugins::BatchedLogging
    # is unable to modify the read_only @payload attribute of Resque::Job
    def args_with_removing_batched_options
      arguments = @payload['args']
      options = arguments.last
      queued_with_batching = options && options.is_a?(Hash) && options.keys.include?(:batched_log_group)
      if queued_with_batching && (batch_name = options[:batched_log_group])
        # Remove our {:batched_log_group => "BatchGroupName"} options hash before the arguments reaches the job
        arguments.pop
        # Since we had to remove the argument, we'll flag a variable on the job class itself to mark the batch_name
        payload_class.start_logging_batched(batch_name) if payload_class.respond_to?(:start_logging_batched)
      end
      args_without_removing_batched_options
    end
    alias_method :args_without_removing_batched_options, :args
    alias_method :args, :args_with_removing_batched_options

  end
end
