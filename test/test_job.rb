require 'helper'

class TestJob < MiniTest::Unit::TestCase

  def test_overloading
    standard_options = [1,2,3, {:my => :options}]
    batched_options = standard_options + [{:batched_log_group => "MyGroup"}]
    standard_payload = {'class' => SampleJob, 'args' => standard_options}
    batched_payload = {'class' => SampleJob, 'args' => batched_options}

    batched_job = Resque::Job.new('test_job_queue', batched_payload)
    assert !SampleJob.logging_as_batched?, "Job class should have batched flag set to false by default"
    assert_equal standard_options, batched_job.args, "batched option should have been removed from the arguments"
    assert SampleJob.logging_as_batched?, "batched flag should have been set by detecting the options in the arguments"
    batched_job.perform
    assert !SampleJob.logging_as_batched?, "batched flag should have been turned off after performing"

    singular_job = Resque::Job.new('test_job_queue', standard_payload)
    assert_equal standard_options, singular_job.args
    assert !SampleJob.logging_as_batched?, "batched flag should not get turned on for non batched job queueing"
    singular_job.perform
    assert !SampleJob.logging_as_batched?, "batched flag should stil not be turned on"
  end

end