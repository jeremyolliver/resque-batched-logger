require 'helper'

class TestBatchedLogging < MiniTest::Unit::TestCase

  def teardown
    Resque.redis.flushdb
    puts "Clearing the log"
    `echo ''> log/batched_jobs.log`
  end

  def test_class_methods
    assert SampleJob.respond_to?(:batched), "#batched should be defined on the job class"
    assert SampleJob.respond_to?(:around_perform_log_as_batched), "#around_perform_log_as_batched should be defined on the job class"
    assert SampleModuleJob.respond_to?(:batched), "#batched should be defined on the job module"
    assert SampleModuleJob.respond_to?(:around_perform_log_as_batched), "#around_perform_log_as_batched should be defined on the job module"
  end
  
  def test_enqueueing_a_batch
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    SampleJob.batched(:batch_name => "Daily SampleGroup run") do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    expected_job_list = arguments.collect {|j| [SampleJob] + j + [{:batched_log_group => "Daily SampleGroup run"}] } + [Resque::Plugins::BatchedLogger, "Daily SampleGroup run"]
    assert_equal expected_job_list, Resque.test_jobs.collect(&:args), "Enqueued arguments should have a batch name hash appened"

    Resque.perform_test_jobs
    assert_empty Resque.test_jobs, "Queue should be empty"
  end
  
  def test_enqueueing_without_batched
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    arguments.each do |args|
      Resque.enqueue(SampleJob, *args)
    end
    expected_job_list = arguments.collect {|j| [SampleJob] + j }
    assert_equal expected_job_list, Resque.test_jobs.collect(&:args), "Enqueued arguments should be unmodified"

    Resque.perform_test_jobs
    assert_empty Resque.test_jobs, "Queue should be empty"
  end

end
