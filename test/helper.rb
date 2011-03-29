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
# Namespace our tests, because we'll be flushing the redis db
Resque.redis = Redis::Namespace.new('batched-logger/test:', :redis => Resque.redis)

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'resque-batched-logger'
require 'shared_utilities'

class MiniTest::Unit::TestCase
end

def global_teardown
  Resque.redis.flushdb
  Resque.clear_test_jobs
  SampleJob.clear_history
  SampleModuleJob.clear_history
  FileUtils.rm(Resque::Plugins::BatchedLogger::LOG_FILE) if File.exist?(Resque::Plugins::BatchedLogger::LOG_FILE)
end


MiniTest::Unit.autorun
