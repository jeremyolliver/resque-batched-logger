require 'helper'

class TestBatchedLogging < MiniTest::Unit::TestCase

  def test_class_methods
    defined_methods = [:batched, :around_perform_log_as_batched, :group_batched_name, :start_logging_batched, :stop_logging_batched]
    [SampleJob, SampleModuleJob].each do |klass|
      defined_methods.each do |meth_name|
        assert klass.respond_to?(meth_name), "##{meth_name} should be defined on #{klass.to_s}"
      end
    end
  end

  def test_flagging_batched
    batch_name = "ThatBatchName"
    assert SampleJob.group_batched_name.nil?
    SampleJob.start_logging_batched(batch_name)
    assert_equal batch_name, SampleJob.group_batched_name
    SampleJob.stop_logging_batched
    assert SampleJob.group_batched_name.nil?
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
    assert_equal arguments, SampleJob.job_history, "The processing job should have recieved the arguments without the :batched_log_group options hash"
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
    assert_equal arguments, SampleJob.job_history, "The arguments recieved by the actual job should have been unmodified"
    assert_empty Resque.test_jobs, "Queue should be empty"
  end

  def test_single_jobs_dont_interrupt_batch
    arguments = [[1,2,3], [4,5], [5,6,{:custom => :options}]]
    batch_name = "Daily SampleGroup run"
    SampleJob.batched(:batch_name => batch_name) do
      enqueue(*arguments[0]) # Enqueue the first job as a batch
      Resque.enqueue(SampleJob, *arguments[1]) # Enqueueing a non batched job in the middle of the batch being queued up (should be processed independently)
      enqueue(*arguments[2]) # Enqueueing a second batched job
    end
    assert_equal 4, Resque.test_jobs.size, "3 jobs + the logger job should have been queued"
    assert_equal 2, Resque.redis.get("#{sanitize_batch(batch_name)}:jobcount").to_i, "Only 2 jobs should be counted as on the queue"
    Resque.perform_test_jobs(:limit => 3) # Process just the first 3 jobs (2 batched, 1 individual, don't process the logs yet)
    assert_equal arguments, SampleJob.job_history
    assert_equal 2, Resque.redis.llen("batch_stats:#{sanitize_batch(batch_name)}")
    Resque.perform_test_jobs # Do the log processing
    assert_empty Resque.test_jobs
  end

  def teardown
    global_teardown
  end

end
