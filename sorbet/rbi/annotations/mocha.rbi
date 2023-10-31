# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module Mocha::API
  sig { params(arguments: T.untyped).returns(Mocha::Mock) }
  def mock(*arguments); end

  sig { params(arguments: T.untyped).returns(T.untyped) }
  def stub(*arguments); end
end

module Mocha::ClassMethods
  sig { returns(Mocha::Mock) }
  def any_instance; end
end

class Mocha::Expectation
  sig { params(expected_parameters_or_matchers: T.untyped, kwargs: T.untyped, matching_block: T.nilable(T.proc.params(actual_parameters: T.untyped).void)).returns(Mocha::Expectation) }
  def with(*expected_parameters_or_matchers, **kwargs, &matching_block); end

  sig { params(values: T.untyped).returns(Mocha::Expectation) }
  def returns(*values); end
end

module Mocha::ObjectMethods
  sig { params(expected_methods_vs_return_values: T.untyped).returns(Mocha::Expectation) }
  def expects(expected_methods_vs_return_values); end

  sig { params(stubbed_methods_vs_return_values: T.untyped).returns(Mocha::Expectation) }
  def stubs(stubbed_methods_vs_return_values); end
end
