require 'helper'

class TestBatchedLogger < MiniTest::Unit::TestCase

  def test_log_format
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    batch_name = "SampleJob"
    SampleJob.batched do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    Resque.perform_test_jobs
    logged_data = File.read(Resque::Plugins::BatchedLogger::LOG_FILE)
    assert_message_logged_with_valid_times(logged_data, Regexp.new("==== Batched jobs \'#{batch_name}\' : logged at (.*) ===="))
    assert logged_data.match(/Jobs Enqueued: 2/), "log should include number of jobs enqueued"
    assert logged_data.match(/Jobs Processed: 2/), "log should include number of jobs processed"
    assert_message_logged_with_valid_times(logged_data, /Batch started: (.*)/)
    assert_message_logged_with_valid_times(logged_data, /Batch finished: (.*)/)
    assert logged_data.match(/Batch total run time: [\d\.]+ seconds/), "log should include total run time"
    assert logged_data.match(/Batch average per job: [\d\.]+ seconds/), "log should include average time per job"
    assert logged_data.match(/Total time spent across all workers: [\d\.]+ seconds/), "log should total time spent processing"

    assert_empty Resque.redis.keys("*:jobcount")
    assert_empty Resque.redis.keys("batch_stats:*")
  end

  def test_logger_running_before_jobs_finished
    Resque::Plugins::BatchedLogger.perform("SampleJob") # Should do no work
    assert_empty Resque.test_jobs
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    SampleJob.batched do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    assert_equal 3, Resque.test_jobs.size
    Resque.test_jobs.pop.perform # Try doing the batch logger first, should be requeued
    assert_equal 3, Resque.test_jobs.size, "The batch logger should have been requeued"
    Resque.perform_test_jobs
    assert_empty Resque.test_jobs
  end

  def test_requeue_all
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    SampleJob.batched do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    assert_equal 3, Resque.test_jobs.size
    assert Resque.test_jobs.collect {|job| job.args.first }.include?(Resque::Plugins::BatchedLogger)
    Resque.test_jobs.pop # Delete the batched logger job without performing it
    assert !Resque.test_jobs.collect {|job| job.args.first }.include?(Resque::Plugins::BatchedLogger)
    Resque::Plugins::BatchedLogger.requeue_all
    assert_equal 3, Resque.test_jobs.size
    assert Resque.test_jobs.collect {|job| job.args.first }.include?(Resque::Plugins::BatchedLogger)
  end

  def teardown
    global_teardown
  end

  protected

  # Line must match overall Regexp 'format', & any selected options with an () in the regexp must be a valid time string
  def assert_message_logged_with_valid_times(string, format)
    matches = string.match(format)
    assert matches, "input #{string} did not match the specified format: #{format.inspect}"
    matches[1..-1].each do |m|
      assert valid_date?(m), "Expected #{m} to be a valid date"
    end
  end

  # Returns true if the string's Year, Month and Day can be correctly determined
  def valid_date?(string)
    Date.parse(string)
  end

end