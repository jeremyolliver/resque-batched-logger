require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'minitest/unit'
require 'resque'

# Namespace our tests
Resque.redis = Redis::Namespace.new('batched-logger/test:', :redis => Resque.redis)

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'resque-batched-logger'
require 'shared_utilities'

class MiniTest::Unit::TestCase
  # def setup
  #   global_teardown
  # end
end

def global_teardown
  # Don't do a flushdb on redis, that doesn't respect the namespace
  Resque.redis.flushdb
  Resque.redis.keys("*:jobcount").each {|k| Resque.redis.del("'#{k.to_s}'") }     # Clear our job count
  Resque.redis.keys("batch_stats:*").each {|k| Resque.redis.del("'#{k.to_s}'") }  # Clear the lists of job stats
  Resque.clear_test_jobs
  SampleJob.clear_history
  SampleModuleJob.clear_history
  FileUtils.rm(Resque::Plugins::BatchedLogger::LOG_FILE) if File.exist?(Resque::Plugins::BatchedLogger::LOG_FILE)
end
global_teardown


MiniTest::Unit.autorun
