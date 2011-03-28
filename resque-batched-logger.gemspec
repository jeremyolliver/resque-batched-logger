# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "resque-batched-logger/version"

Gem::Specification.new do |s|
  s.name        = "resque-batched-logger"
  s.version     = Resque::Batched::Logger::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Jeremy Olliver"]
  s.email       = ["jeremy.olliver@gmail.com"]
  s.homepage    = "http://github.com/heaps/resque-batched-logger"
  s.summary     = %q{Allows resque jobs to be run in batches with aggregate logging}
  s.description = %q{Allows resque jobs to be run in batches with aggregate logging, timing and statistics}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'resque'
end
