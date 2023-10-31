# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "sorbet-runtime"

# Analytics stubbing

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup do
      # Analytics stubbing
      Analytics.stubs(:on_user_authentication)
      Analytics.stubs(:on_organization_creation)
    end
  end
end
