lib_dir = File.dirname(__FILE__)
require File.join(lib_dir, 'resque/plugins/batched_logging')
require File.join(lib_dir, 'resque/plugins/batched_logger')

if RUBY_VERSION < "1.9"
  warn("Warning - Batch job runtimes may be off. It is *highly* recommended to use SystemTimer >= 1.1 with Resque on ruby 1.8") unless defined?(SystemTimer)
end
