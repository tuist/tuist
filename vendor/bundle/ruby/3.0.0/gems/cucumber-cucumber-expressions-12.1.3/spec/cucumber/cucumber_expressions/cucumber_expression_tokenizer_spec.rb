require 'yaml'
require 'json'
require 'cucumber/cucumber_expressions/cucumber_expression_tokenizer'
require 'cucumber/cucumber_expressions/errors'

module Cucumber
  module CucumberExpressions
    describe 'Cucumber expression tokenizer' do
      Dir['testdata/tokens/*.yaml'].each do |testcase|
        expectation = YAML.load_file(testcase) # encoding?
        it "#{testcase}" do
          tokenizer = CucumberExpressionTokenizer.new
          if expectation['exception'].nil?
            tokens = tokenizer.tokenize(expectation['expression'])
            token_hashes = tokens.map{|token| token.to_hash}
            expect(token_hashes).to eq(JSON.parse(expectation['expected']))
          else
            expect { tokenizer.tokenize(expectation['expression']) }.to raise_error(expectation['exception'])
          end
        end
      end
    end
  end
end
