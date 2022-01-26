require 'yaml'
require 'json'
require 'cucumber/cucumber_expressions/cucumber_expression_parser'
require 'cucumber/cucumber_expressions/errors'

module Cucumber
  module CucumberExpressions
    describe 'Cucumber expression parser' do
      Dir['testdata/ast/*.yaml'].each do |testcase|
        expectation = YAML.load_file(testcase) # encoding?
        it "#{testcase}" do
          parser = CucumberExpressionParser.new
          if expectation['exception'].nil?
            node = parser.parse(expectation['expression'])
            node_hash = node.to_hash
            expect(node_hash).to eq(JSON.parse(expectation['expected']))
          else
            expect { parser.parse(expectation['expression']) }.to raise_error(expectation['exception'])
          end
        end
      end
    end
  end
end
