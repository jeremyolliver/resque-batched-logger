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

  def test_queuing_multiple_batches
    arguments = [[1,2,3], [4,5], [5,6,{:custom => :options}]]
    # Should be able to do this twice without raising an error
    2.times do
      SampleJob.batched do
        arguments.each do |args|
          enqueue(*args)
        end
      end
      assert_equal 4, Resque.test_jobs.size, "3 jobs + the logger job should have been queued"
      Resque.perform_test_jobs
      assert_empty Resque.test_jobs
    end
  end

  def test_queueing_nothing
    SampleJob.batched do
      [].each do |args|
        enqueue(*args)
      end
    end
    Resque.perform_test_jobs
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
    # Now test that when the logger runs, things are reset as they should be
    Resque.perform_test_jobs # Do the log processing
    assert_empty Resque.test_jobs
    assert_nil Resque.redis.get("BatchedSampleJob:jobcount"), "should not have any jobcount"
    assert_equal 0, Resque.redis.llen("batch_stats:BatchedSampleJob"), "should have no batch stats"
  end

  def test_calling_batched_with_no_block
    assert_raises(RuntimeError) do
      SampleJob.batched
    end
  end

  def test_queueing_multiple_jobs
    SampleJob.batched do
      enqueue(1,2,3)
    end
    assert_raises(Resque::Plugins::BatchedLogging::BatchExists) do
      SampleJob.batched do
        enqueue(3,4,5)
      end
    end
  end

  def test_custom_enqueueing_methods
    arguments = [[1,4,5], [1,3,6]]
    CustomJob.batched do
      arguments.each do |args|
        enqueue(*args)
      end
    end
    assert_equal 2, CustomJob.custom_created_history.size
    assert_equal 3, Resque.test_jobs.size
    SuperCustomJob.batched do
      arguments.each do |args|
        enqueue(*args)
      end
    end
    assert_equal 2, SuperCustomJob.custom_enqueued_history.size
    assert_equal 6, Resque.test_jobs.size
  end

  def test_failed_jobs_dont_break_anything
    BuggyJob.batched { enqueue }
    assert_equal 2, Resque.test_jobs.size, "2 jobs (the enqueued one and the logger) should have been queued"
    assert_equal 1, Resque.redis.get("BuggyJob:jobcount").to_i, "should have listed 1 job on the queue"
    assert_equal 0, Resque.redis.llen("batch_stats:BuggyJob"), "should not have processed batch stats yet"

    # Now test that when the queued job is run and fails, it still adds a batch stat, and doesn't affect jobcount
    assert_raises(RuntimeError) { Resque.perform_test_jobs(:limit => 1) } # this raises an error when the job executes
    assert_equal 1, Resque.test_jobs.size, "1 job should be remaining on the queue"
    assert_equal 1, Resque.redis.get("BuggyJob:jobcount").to_i, "should have no more of this job counted"
    assert_equal 1, Resque.redis.llen("batch_stats:BuggyJob"), "should have 1 processed batch stats"

    # Now test that when the logger runs, things are reset as they should be
    Resque.perform_test_jobs # Do the log processing
    assert_empty Resque.test_jobs
    assert_nil Resque.redis.get("BuggyJob:jobcount"), "should not have any jobcount"
    assert_equal 0, Resque.redis.llen("batch_stats:BuggyJob"), "should have no batch stats"
  end

  def teardown
    global_teardown
  end

end
