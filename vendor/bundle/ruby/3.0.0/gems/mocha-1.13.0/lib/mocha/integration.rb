require 'mocha/integration/test_unit'
require 'mocha/integration/mini_test'

module Mocha
  module Integration
    def self.activate
      return unless [Integration::TestUnit, Integration::MiniTest].map(&:activate).none?
      raise "Test::Unit or Minitest must be loaded *before* `require 'mocha/setup'`."
    end
  end
end
