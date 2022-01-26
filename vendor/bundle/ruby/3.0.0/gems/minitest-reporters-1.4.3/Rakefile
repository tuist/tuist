require "bundler/gem_tasks"
require "rake/testtask"
require 'rubocop/rake_task'

task :default => :test
Rake::TestTask.new do |t|
  t.pattern = "test/{unit,integration}/**/*_test.rb"
  t.verbose = true
end

rubymine_home = [
  ENV["RUBYMINE_HOME"],
  "../rubymine-contrib/ruby-testing/src/rb/testing/patch/common",
  "/Applications/RubyMine.app/Contents/rb/testing/patch/common",
].compact.detect { |d| Dir.exist?(d) }

Rake::TestTask.new("test:gallery") do |t|
  t.pattern = "test/gallery/**/*_test.rb"
  t.verbose = true
  t.libs << rubymine_home
end

# - RubyMineReporter must be tested separately inside of RubyMine
# - JUnitReporter normally writes to `test/reports` instead of stdout
task :gallery do
  unless rubymine_home
    warn "To see RubyMineReporter supply RUBYMINE_HOME= or git clone git://git.jetbrains.org/idea/contrib.git ../rubymine-contrib"
    exit 1
  end

  [
    "Pride",
    "DefaultReporter",
    "JUnitReporter",
    "ProgressReporter",
    "RubyMateReporter",
    "SpecReporter",
    "RubyMineReporter",
    "HtmlReporter",
    "MeanTimeReporter",
  ].each do |reporter|
    puts
    puts "-" * 72
    puts "Running gallery tests using #{reporter}..."
    puts "-" * 72
    puts

    sh "rake test:gallery REPORTER=#{reporter}" do
      # Ignore failures. They're expected when you are running the gallery
      # test suite.
    end
    sh "cat test/reports/*" if reporter == "JUnitReporter"
  end
end

task :reset_statistics do
  require 'minitest/reporters/mean_time_reporter'
  Minitest::Reporters::MeanTimeReporter.reset_statistics!
  puts "The mean time reporter statistics have been reset."
  exit 0
end

desc 'Run RuboCop on the lib directory'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.patterns = ['lib/**/*.rb']
  # only show the files with failures
  task.formatters = ['clang']
  # don't abort rake on failure
  task.fail_on_error = false
end
