# Test Helper classes
class SampleJob
  @@job_history = []
  include Resque::Plugins::BatchedLogging

  def self.perform(*args)
    @@job_history << args
    sleep 1
  end
end

module SampleModuleJob
  @@job_history = []
  include Resque::Plugins::BatchedLogging

  def self.perform(*args)
    @@job_history << args
    sleep 1
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
  end
  def self.enqueue(*args)
    @@test_jobs << Resque::TestJob.new(*args)
  end
  def self.test_jobs
    @@test_jobs
  end
  def self.perform_test_jobs
    while job = @@test_jobs.shift # Pop from the front of the array of pending jobs
      # Process the job according to the given class
      arguments = job.args
      klass = arguments.shift
      klass.perform(*arguments)
    end
  end
end