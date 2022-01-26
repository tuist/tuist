require "bundler/setup"
require "minitest/autorun"
require "minitest/reporters"

ENV['MINITEST_REPORTERS_MONO'] = 'yes'
module MinitestReportersTest
  class TestCase < Minitest::Test
  end
end

# Testing the built-in reporters using automated unit testing would be extremely
# brittle. Consequently, there are no unit tests for them.  If you'd like to run
# all the reporters sequentially on a fake test suite, run `rake gallery`.

if ENV["REPORTER"] == "Pride"
  require "minitest/pride"
elsif ENV["REPORTER"]
  reporter_klass = Minitest::Reporters.const_get(ENV["REPORTER"])
  Minitest::Reporters.use!(reporter_klass.new)
else
  Minitest::Reporters.use!(Minitest::Reporters::DefaultReporter.new)
end
