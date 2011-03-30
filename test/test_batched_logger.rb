require 'helper'

class TestBatchedLogger < MiniTest::Unit::TestCase

  require 'time'
  require 'parsedate'

  def test_log_format
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    batch_name = sanitize_batch("Daily SampleGroup run")
    SampleJob.batched(:batch_name => batch_name) do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    Resque.perform_test_jobs
    logged_data = File.read(Resque::Plugins::BatchedLogger::LOG_FILE)
    assert_message_logged_with_valid_times(logged_data, Regexp.new("==== Batched jobs \'#{batch_name}\' : logged at (.*) ===="))
    assert_message_logged_with_valid_times(logged_data, /batch started processing at: (.*)/)
    assert_message_logged_with_valid_times(logged_data, /batch finished processing at: (.*)/)
    assert logged_data.match(/Total run time for batch: [\d\.]+ seconds/), "log should include total run time"
    assert logged_data.match(/Jobs Completed: [\d]+/), "log should include number of jobs completed"
    assert logged_data.match(/Average time per job: [\d\.]+ seconds/), "log should include average time per job"
    assert logged_data.match(/Total time spent processing jobs: [\d\.]+ seconds/), "log should total time spent processing"
    assert_message_logged_with_valid_times(logged_data, Regexp.new("==== Batched jobs \'#{batch_name}\' completed at (.*) took [\\d\\.]+ seconds ===="))

    assert total_run_time = logged_data.match(/Total run time for batch: ([\d\.]+) seconds/)[1]
    assert final_completion_time = logged_data.match(Regexp.new("==== Batched jobs \'#{batch_name}\' completed at .* took ([\\d\\.]+) seconds ===="))[1]
    assert_equal(total_run_time, final_completion_time, "Final completion length should match total time for batch")
  end
  
  def test_logger_running_before_jobs_finished
    batch_name = sanitize_batch("My Batch Name")
    Resque::Plugins::BatchedLogger.perform(batch_name) # Should do no work
    assert_empty Resque.test_jobs
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    SampleJob.batched(:batch_name => batch_name) do
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

  def valid_date?(string)
    # Returns true if the string's Year, Month and Day can be correctly determined
    # parsedate returns an array of values for a date/time starting with year, decreasing in size
    (d = ParseDate.parsedate(string)) && d[0..2].compact.size == 3
  end

end