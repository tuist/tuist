require 'cucumber/cucumber_expressions/expression_factory'

module Cucumber
  module CucumberExpressions
    describe ExpressionFactory do
      before do
        @expression_factory = ExpressionFactory.new(ParameterTypeRegistry.new)
      end

      it 'creates a RegularExpression' do
        expect(@expression_factory.create_expression(/x/).class).to eq(RegularExpression)
      end

      it 'creates a CucumberExpression' do
        expect(@expression_factory.create_expression('{int}').class).to eq(CucumberExpression)
      end
    end
  end
end
