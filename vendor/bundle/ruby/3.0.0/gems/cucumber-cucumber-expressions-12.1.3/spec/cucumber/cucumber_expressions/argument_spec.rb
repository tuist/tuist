require 'cucumber/cucumber_expressions/argument'
require 'cucumber/cucumber_expressions/tree_regexp'
require 'cucumber/cucumber_expressions/parameter_type_registry'

module Cucumber
  module CucumberExpressions
    describe Argument do
      it 'exposes parameter_type' do
        tree_regexp = TreeRegexp.new(/three (.*) mice/)
        parameter_type_registry = ParameterTypeRegistry.new
        arguments = Argument.build(tree_regexp, "three blind mice", [parameter_type_registry.lookup_by_type_name("string")])
        argument = arguments[0]
        expect(argument.parameter_type.name).to eq("string")
      end
    end
  end
end
