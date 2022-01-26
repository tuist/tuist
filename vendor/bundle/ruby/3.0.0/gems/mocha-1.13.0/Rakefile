require 'bundler'
Bundler::GemHelper.install_tasks
require 'bundler/setup'

require 'rake/testtask'

desc 'Run all tests'
task 'default' => ['test', 'test:performance']

desc 'Run tests'
task 'test' do
  if (test_library = ENV['MOCHA_RUN_INTEGRATION_TESTS'])
    Rake::Task["test:integration:#{test_library}"].invoke
  else
    Rake::Task['test:units'].invoke
    Rake::Task['test:acceptance'].invoke
  end
end

namespace 'test' do # rubocop:disable Metrics/BlockLength
  unit_tests = FileList['test/unit/**/*_test.rb']
  all_acceptance_tests = FileList['test/acceptance/*_test.rb']
  ruby186_incompatible_acceptance_tests = FileList['test/acceptance/stub_class_method_defined_on_*_test.rb'] + FileList['test/acceptance/stub_instance_method_defined_on_*_test.rb']
  ruby186_compatible_acceptance_tests = all_acceptance_tests - ruby186_incompatible_acceptance_tests

  desc 'Run unit tests'
  Rake::TestTask.new('units') do |t|
    t.libs << 'test'
    t.test_files = unit_tests
    t.verbose = true
    t.warning = true
  end

  desc 'Run acceptance tests'
  Rake::TestTask.new('acceptance') do |t|
    t.libs << 'test'
    t.test_files = if defined?(RUBY_VERSION) && (RUBY_VERSION >= '1.8.7')
                     all_acceptance_tests
                   else
                     ruby186_compatible_acceptance_tests
                   end
    t.verbose = true
    t.warning = true
  end

  namespace 'integration' do
    desc 'Run MiniTest integration tests (intended to be run in its own process)'
    Rake::TestTask.new('minitest') do |t|
      t.libs << 'test'
      t.test_files = FileList['test/integration/mini_test_test.rb']
      t.verbose = true
      t.warning = true
    end

    desc 'Run Test::Unit integration tests (intended to be run in its own process)'
    Rake::TestTask.new('test-unit') do |t|
      t.libs << 'test'
      t.test_files = FileList['test/integration/test_unit_test.rb']
      t.verbose = true
      t.warning = true
    end
  end

  # require 'rcov/rcovtask'
  # Rcov::RcovTask.new('coverage') do |t|
  #   t.libs << 'test'
  #   t.test_files = unit_tests + acceptance_tests
  #   t.verbose = true
  #   t.warning = true
  #   t.rcov_opts << '--sort coverage'
  #   t.rcov_opts << '--xref'
  # end

  desc 'Run performance tests'
  task 'performance' do
    require File.join(File.dirname(__FILE__), 'test', 'acceptance', 'stubba_example_test')
    require File.join(File.dirname(__FILE__), 'test', 'acceptance', 'mocha_example_test')
    iterations = 1000
    puts "\nBenchmarking with #{iterations} iterations..."
    [MochaExampleTest, StubbaExampleTest].each do |test_case|
      puts "#{test_case}: #{benchmark_test_case(test_case, iterations)} seconds."
    end
  end
end

begin
  require 'rubocop/rake_task'
  if RUBY_VERSION >= '2.2.0' && (defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby') && ENV['MOCHA_RUN_INTEGRATION_TESTS'].nil?
    RuboCop::RakeTask.new
    task 'test' => 'rubocop'
  end
rescue LoadError # rubocop:disable Lint/HandleExceptions
end

# rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
def benchmark_test_case(klass, iterations)
  require 'benchmark'
  require 'mocha/detection/mini_test'

  if defined?(MiniTest)
    minitest_version = Gem::Version.new(Mocha::Detection::MiniTest.version)
    if Gem::Requirement.new('>= 5.0.0').satisfied_by?(minitest_version)
      result = Benchmark.realtime { iterations.times { |_i| klass.run(MiniTest::CompositeReporter.new) } }
      MiniTest::Runnable.runnables.delete(klass)
      result
    else
      MiniTest::Unit.output = StringIO.new
      Benchmark.realtime { iterations.times { |_i| MiniTest::Unit.new.run([klass]) } }
    end
  else
    load 'test/unit/ui/console/testrunner.rb' unless defined?(Test::Unit::UI::Console::TestRunner)
    unless @silent_option
      begin
        load 'test/unit/ui/console/outputlevel.rb' unless defined?(Test::Unit::UI::Console::OutputLevel::SILENT)
        @silent_option = { :output_level => Test::Unit::UI::Console::OutputLevel::SILENT }
      rescue LoadError
        @silent_option = Test::Unit::UI::SILENT
      end
    end
    Benchmark.realtime { iterations.times { Test::Unit::UI::Console::TestRunner.run(klass, @silent_option) } }
  end
end
# rubocop:enable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity

if ENV['MOCHA_GENERATE_DOCS']
  require 'yard'

  desc 'Remove generated documentation'
  task 'clobber_yardoc' do
    `rm -rf ./docs`
  end

  task 'docs_environment' do
    unless ENV['GOOGLE_ANALYTICS_WEB_PROPERTY_ID']
      puts "\nWarning: GOOGLE_ANALYTICS_WEB_PROPERTY_ID was not defined\n\n"
    end
  end

  desc 'Generate documentation'
  YARD::Rake::YardocTask.new('yardoc' => 'docs_environment') do |task|
    task.options = ['--title', "Mocha #{Mocha::VERSION}", '--fail-on-warning']
  end

  task 'checkout_docs_cname' do
    `git checkout docs/CNAME`
  end

  task 'checkout_docs_js' do
    `git checkout docs/js/app.js`
    `git checkout docs/js/jquery.js`
  end

  desc 'Generate documentation'
  task 'generate_docs' => %w[clobber_yardoc yardoc checkout_docs_cname checkout_docs_js]
end

task 'release' => 'default'
