$VERBOSE = true

require 'ice_nine'
require 'regexp_property_values'
require_relative 'support/capturing_stderr'
require_relative 'support/shared_examples'

req_warn = capturing_stderr { require('regexp_parser') || fail('pre-required') }
req_warn.empty? || fail("requiring parser generated warnings:\n#{req_warn}")

RS = Regexp::Scanner
RL = Regexp::Lexer
RP = Regexp::Parser
RE = Regexp::Expression
T = Regexp::Syntax::Token

include Regexp::Expression

def ruby_version_at_least(version)
  Gem::Version.new(RUBY_VERSION.dup) >= Gem::Version.new(version)
end

RSpec.configure do |config|
  config.around(:example) do |example|
    # treat unexpected warnings as failures
    expect { example.run }.not_to output.to_stderr
  end
end
