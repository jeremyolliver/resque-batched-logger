# Test Helper classes
class SampleJob
  @@job_history = []
  @queue = 'sample_job_queue'
  include Resque::Plugins::BatchedLogging

  def self.perform(*args)
    @@job_history << args
    sleep(0.5)
  end

  def self.job_history
    @@job_history
  end
  def self.clear_history
    @@job_history = []
  end
end

class BatchedSampleJob < SampleJob
  # This subclass is simply for namespacing batched 'SampleJob's
end

module SampleModuleJob
  @@job_history = []
  include Resque::Plugins::BatchedLogging

  def self.perform(*args)
    @@job_history << args
    sleep(0.5)
  end
  def self.job_history
    @@job_history
  end
  def self.clear_history
    @@job_history = []
  end
end

# Test Overrides
module Resque
  @@test_jobs = []
  class TestJob
    attr_accessor :args
    def initialize(*args)
      @args = args
    end
    def perform
      local_payload = {'class' => @args.shift, 'args' => @args }
      # Perform using Resque::Job, because that's what implements the hooks we need to test
      Resque::Job.new('test_queue', local_payload).perform
    end
  end
  def self.enqueue(*args)
    @@test_jobs << Resque::TestJob.new(*args)
  end
  def self.test_jobs
    @@test_jobs
  end
  def self.clear_test_jobs
    @@test_jobs = []
  end
  def self.perform_test_jobs(options = {})
    number_processed = 0
    while job = @@test_jobs.shift # Pop from the front of the array of pending jobs
      job.perform
      number_processed +=1
      break if number_processed == options[:limit]
    end
    number_processed
  end
end
