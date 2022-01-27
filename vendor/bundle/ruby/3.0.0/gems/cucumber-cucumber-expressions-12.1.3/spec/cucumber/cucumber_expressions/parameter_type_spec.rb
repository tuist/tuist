require 'cucumber/cucumber_expressions/parameter_type'

module Cucumber
  module CucumberExpressions
    describe ParameterType do
      it 'does not allow ignore flag on regexp' do
        expect do
          ParameterType.new("case-insensitive", /[a-z]+/i, String, lambda {|s| s}, true, true)
        end.to raise_error(
          CucumberExpressionError,
          "ParameterType Regexps can't use option Regexp::IGNORECASE")
      end
    end
  end
end
