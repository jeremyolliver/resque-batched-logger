require 'helper'

class TestBatchedLogging < MiniTest::Unit::TestCase

  def test_class_methods
    assert SampleJob.respond_to?(:batched), "#batched should be defined on the job class"
    assert SampleJob.respond_to?(:around_perform_log_as_batched), "#around_perform_log_as_batched should be defined on the job class"
    assert SampleModuleJob.respond_to?(:batched), "#batched should be defined on the job module"
    assert SampleModuleJob.respond_to?(:around_perform_log_as_batched), "#around_perform_log_as_batched should be defined on the job module"
  end

  def test_enqueueing_a_batch
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    batch_name = "Daily SampleGroup run"
    SampleJob.batched(:batch_name => batch_name) do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    expected_job_list = arguments.collect {|j| [SampleJob] + j + [{:batched_log_group => sanitize_batch(batch_name)}] } # Jobs should be enqueued with correct Job class, and batch group
    expected_job_list << [Resque::Plugins::BatchedLogger, sanitize_batch(batch_name)] # We expect the BatchedLogger to have been enqueued as well
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
    assert_equal arguments, SampleJob.job_history
    assert_empty Resque.test_jobs, "Queue should be empty"
  end

  def teardown
    global_teardown
  end

end
