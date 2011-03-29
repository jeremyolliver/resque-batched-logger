require 'helper'

class TestBatchedLogger < MiniTest::Unit::TestCase
  
  require 'time'
  
  def test_log_format
    arguments = [[1,2,3], [5,6,{:custom => :options}]]
    batch_name = "Daily SampleGroup run"
    SampleJob.batched(:batch_name => batch_name) do
      arguments.each do |arg|
        enqueue(*arg)
      end
    end
    Resque.perform_test_jobs
    logged_data = File.read(Resque::Plugins::BatchedLogger::LOG_FILE)
    puts logged_data
    log_lines = logged_data.split("\n")
    assert (m = log_lines[0].match(Regexp.new("==== Batched jobs \'#{batch_name}\' : logged at (.*) ===="))) && Time.parse(m[1]), "log header should be formatted with batch name and valid start time"
    # assert log_lines[1].match(Regexp.new("==== Batched jobs \"#{batch_name}\" : logged at .* ===="))
  end

  def teardown
    global_teardown
  end

end