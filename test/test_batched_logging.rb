require 'helper'

class TestBatchedLogging < MiniTest::Unit::TestCase

  def test_class_extensions
    defined_methods = [:batched, :around_perform_log_as_batched]
    [SampleJob, SampleModuleJob, BatchedSampleJob].each do |klass|
      defined_methods.each do |meth_name|
        assert klass.respond_to?(meth_name), "##{meth_name} should be defined on #{klass.to_s}"
      end
    end
  end

  def test_enqueueing_a_batch
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    SampleJob.batched do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    expected_job_list = arguments.collect {|j| [SampleJob] + j } # Jobs should be enqueued with correct Job class, and batch group
    expected_job_list << [Resque::Plugins::BatchedLogger, "SampleJob"] # We expect the BatchedLogger to have been enqueued as well
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
    SampleJob.batched do
      enqueue(*arguments[0]) # Enqueue the first job as a batch
      Resque.enqueue(SampleJob, *arguments[1]) # Enqueueing a non batched job in the middle of the batch being queued up (should be processed independently)
      enqueue(*arguments[2]) # Enqueueing a second batched job
    end
    assert_equal 4, Resque.test_jobs.size, "3 jobs + the logger job should have been queued"
    assert_equal 2, Resque.redis.get("SampleJob:jobcount").to_i, "should have listed 2 jobs on the queue"
    Resque.perform_test_jobs(:limit => 3) # Process just the first 3 jobs (2 batched, 1 individual, don't process the logs yet)
    assert_equal arguments, SampleJob.job_history
    assert_equal 3, Resque.redis.llen("batch_stats:SampleJob"), "All 3 jobs will have been processed as batched"
    Resque.perform_test_jobs # Do the log processing
    assert_empty Resque.test_jobs
  end

  # Same test as 'test_single_jobs_dont_interrupt_batch', except we'll batch with the subclass, and hence the enqueueing of the superclas won't effect our logged job count
  def test_sub_classed_batch_jobs
    assert BatchedSampleJob.respond_to?(:perform)
    assert_equal SampleJob, BatchedSampleJob.superclass

    arguments = [[1,2,3], [4,5], [5,6,{:custom => :options}]]
    BatchedSampleJob.batched do
      enqueue(*arguments[0]) # Enqueue the first job as a batch
      Resque.enqueue(SampleJob, *arguments[1]) # Enqueueing a non batched job in the middle of the batch being queued up (should be processed independently)
      enqueue(*arguments[2]) # Enqueueing a second batched job
    end
    assert_equal 4, Resque.test_jobs.size, "3 jobs + the logger job should have been queued"
    assert_equal 2, Resque.redis.get("BatchedSampleJob:jobcount").to_i, "should have listed 2 jobs on the queue"
    Resque.perform_test_jobs(:limit => 3) # Process just the first 3 jobs (2 batched, 1 individual, don't process the logs yet)
    assert_equal arguments, SampleJob.job_history
    assert_equal 2, Resque.redis.llen("batch_stats:BatchedSampleJob"), "Only the 2 batched jobs should have been processed as batched"
    Resque.perform_test_jobs # Do the log processing
    assert_empty Resque.test_jobs
  end

  def teardown
    global_teardown
  end

end
