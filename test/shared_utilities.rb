# Test Helper classes
class SampleJob
  @@job_history = []
  include Resque::Plugins::BatchedLogging

  def self.perform(*args)
    @@job_history << args
    sleep 1
  end

  def self.job_history
    @@job_history
  end
  def self.clear_history
    @@job_history = []
  end
end

module SampleModuleJob
  @@job_history = []
  include Resque::Plugins::BatchedLogging

  def self.perform(*args)
    @@job_history << args
    sleep 1
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
      payload = {'class' => @args.shift, 'args' => @args }
      # Perform using Resque::Job, because that's what implements the hooks we need to test
      Resque::Job.new('test_queue', payload).perform
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
  def self.perform_test_jobs
    while job = @@test_jobs.shift # Pop from the front of the array of pending jobs
      job.perform
    end
  end
end
