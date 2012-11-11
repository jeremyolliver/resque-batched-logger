# Resque Batched Logger [![Build Status](https://secure.travis-ci.org/jeremyolliver/gvis.png)](http://travis-ci.org/jeremyolliver/gvis)

ResqueBatchedLogger is an extension to [Resque](https://github.com/defunkt/resque).
It provides timing and logging for a 'batch' (logical grouping) of enqueued
background jobs.

For example, if you have a daily import process which spawns a large amount of
several types of jobs, which collectively take a couple of hours to complete,
this extension lets you track the total time, when jobs finished, and the amount
of time each job took to execute.

Paid Alternatives - The newly released [Sidekiq](https://github.com/mperham/sidekiq) library which is a Resque alternative does have support for batches and notfication - this is currently a paid 'pro' feature

## Threading Caveats

The .batched method sets class level variables to be able to transparently affect any enqueued jobs within the block scope.
This is likely not threadsafe which may cause jobs enqueued in one thread to read the altered class level variables and
be enqueued as part of the batch that's being loaded in another thread. The batched job tracking will stop counting when it sees
the number of jobs coming through marked as batch as the expected number.

## Ruby 1.8

When using with a Ruby 1.8 implementation (for example Standard MRI ruby, or Ruby Enterprise Edition) it is highly recommended to use the gem SystemTimer >= 1.1
This is something that's required to get accurated timings for resque within ruby 1.8, which is of higher importance when using this gem because the tracking
of the batches depends on checking runtimes and does aggregate stats for your batches

## Ruby 1.9

Ruby 1.9 incompatible code has now been removed, and the test suite is passing. Though it has not had any significant production testing, which may be advisable

## Installation

    gem install resque-batched-logger

## Usage

First, include the `BatchedLogging` module in your job classes:

    class MyJob
      @queue = :standard
      extend Resque::Plugins::BatchedLogging

      def self.perform(*args)
        # your job implementation
      end
    end

Then, `enqueue` the jobs with the `batched` method on the job class:

    MyJob.batched do
      enqueue(1,2,3, :my => :options)
    end

Finally, start up a new Resque worker to process the 'batched_logger' queue.
Only one should run, so that data is logged in the correct order, and that
priority of that queue should be low (so it runs after the batched jobs).

## Sample Output

The logging of each batch of jobs will be written to a log file at
`log/batched_jobs.log` by the BatchedLogger resque job.

    ==== Batched jobs 'MyJob' : logged at Mon Mar 28 16:25:04 +1300 2011 ====
      batch started processing at: Mon Mar 28 16:23:00 +1300 2011
      batch finished processing at: Mon Mar 28 16:25:02 +1300 2011
      Total run time for batch: 122 seconds
      Jobs Enqueued: 220
      Jobs Processed: 220
      Average time per job: 0.527 seconds
      Total time spent processing jobs: 116 seconds
    ==== Batched jobs 'MyJob' completed at Mon Mar 28 16:25:02 +1300 2011 took 122 seconds ====

## Advanced Usage

For batching jobs of the same type in multiple groups, or if your application
might enqueue jobs of the same type while your batched jobs are running, it is
recommended that you subclass your jobs for a batched class, to allow an
exclusive batch scope.

    class BackendLifting
      @queue = :standard
      extend Resque::Plugins::BatchedLogging

      def self.perform(*args)
        # your job implementation
      end
    end

    class BatchedBackendLifting < BackendLifting
      # This is simply to provide an exclusive scope
    end

This allows you to batch your jobs via:

    BatchedBackendLifting.batched do
      user_ids.each do |id|
        enqueue(id)
      end
    end

Doing the above will prevent any `BackendLifting` jobs your application enqueues
simultaneously from being inadvertently logged as a batched job. This is only
necessary if you want to guarantee there are no additional jobs added to the
logging of your batch, or the ability to enqueue multiple batches at once.

## How it works

The `enqueue` calls within the `batched` block are sent to a proxy, which wraps
the job with logging code, and then calls any defined `enqueue` or `create` class
methods (in that order) on your job class, and if neither is present, will default
to the standard Resque.enqueue.

Jobs will be batched grouped by the job class name, and must be unique so for
running multiple batches at once, see the advanced usage section above.

Log information is stored in redis until all jobs have been processed, and once
all the jobs present in the batch have been performed, the `BatchedJobsLogger`
pulls this information out of redis, aggregates it and outputs it to the logfile
'log/batched_jobs.log'.
