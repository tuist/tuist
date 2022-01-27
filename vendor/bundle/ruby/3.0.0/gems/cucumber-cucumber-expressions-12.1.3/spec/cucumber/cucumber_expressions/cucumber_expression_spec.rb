require 'yaml'
require 'json'
require 'cucumber/cucumber_expressions/cucumber_expression'
require 'cucumber/cucumber_expressions/parameter_type_registry'

module Cucumber
  module CucumberExpressions
    describe CucumberExpression do

      Dir['testdata/expression/*.yaml'].each do |testcase|
        expectation = YAML.load_file(testcase) # encoding?
        it "#{testcase}" do
          parameter_registry = ParameterTypeRegistry.new
          if expectation['exception'].nil?
            cucumber_expression = CucumberExpression.new(expectation['expression'], parameter_registry)
            matches = cucumber_expression.match(expectation['text'])
            values = matches.nil? ? nil : matches.map { |arg| arg.value(nil) }
            expect(values).to eq(JSON.parse(expectation['expected']))
          else
            expect {
              cucumber_expression = CucumberExpression.new(expectation['expression'], parameter_registry)
              cucumber_expression.match(expectation['text'])
            }.to raise_error(expectation['exception'])
          end
        end
      end

      Dir['testdata/regex/*.yaml'].each do |testcase|
        expectation = YAML.load_file(testcase) # encoding?
        it "#{testcase}" do
          parameter_registry = ParameterTypeRegistry.new
          cucumber_expression = CucumberExpression.new(expectation['expression'], parameter_registry)
          expect(cucumber_expression.regexp.source).to eq(expectation['expected'])
        end
      end

      it "documents match arguments" do
        parameter_registry = ParameterTypeRegistry.new

        ### [capture-match-arguments]
        expr = "I have {int} cuke(s)"
        expression = CucumberExpression.new(expr, parameter_registry)
        args = expression.match("I have 7 cukes")
        expect(args[0].value(nil)).to eq(7)
        ### [capture-match-arguments]
      end

      it "matches float" do
        expect(match("{float}", "")).to eq(nil)
        expect(match("{float}", ".")).to eq(nil)
        expect(match("{float}", ",")).to eq(nil)
        expect(match("{float}", "-")).to eq(nil)
        expect(match("{float}", "E")).to eq(nil)
        expect(match("{float}", "1,")).to eq(nil)
        expect(match("{float}", ",1")).to eq(nil)
        expect(match("{float}", "1.")).to eq(nil)

        expect(match("{float}", "1")).to eq([1])
        expect(match("{float}", "-1")).to eq([-1])
        expect(match("{float}", "1.1")).to eq([1.1])
        expect(match("{float}", "1,000")).to eq(nil)
        expect(match("{float}", "1,000,0")).to eq(nil)
        expect(match("{float}", "1,000.1")).to eq(nil)
        expect(match("{float}", "1,000,10")).to eq(nil)
        expect(match("{float}", "1,0.1")).to eq(nil)
        expect(match("{float}", "1,000,000.1")).to eq(nil)
        expect(match("{float}", "-1.1")).to eq([-1.1])

        expect(match("{float}", ".1")).to eq([0.1])
        expect(match("{float}", "-.1")).to eq([-0.1])
        expect(match("{float}", "-.1000001")).to eq([-0.1000001])
        expect(match("{float}", "1E1")).to eq([10.0])
        expect(match("{float}", ".1E1")).to eq([1])
        expect(match("{float}", "E1")).to eq(nil)
        expect(match("{float}", "-.1E-1")).to eq([-0.01])
        expect(match("{float}", "-.1E-2")).to eq([-0.001])
        expect(match("{float}", "-.1E+1")).to eq([-1])
        expect(match("{float}", "-.1E+2")).to eq([-10])
        expect(match("{float}", "-.1E1")).to eq([-1])
        expect(match("{float}", "-.1E2")).to eq([-10])
      end

      it "float with zero" do
        expect(match("{float}", "0")).to eq([0.0])
      end

      it "matches anonymous" do
        expect(match("{}", "0.22")).to eq(["0.22"])
      end

      it "exposes source" do
        expr = "I have {int} cuke(s)"
        expect(CucumberExpression.new(expr, ParameterTypeRegistry.new).source).to eq(expr)
      end

      it "unmatched optional groups have undefined values" do
        parameter_type_registry = ParameterTypeRegistry.new
        parameter_type_registry.define_parameter_type(
            ParameterType.new(
                'textAndOrNumber',
                /([A-Z]+)?(?: )?([0-9]+)?/,
                Object,
                -> (s1, s2) {
                  [s1, s2]
                },
                false,
                true
            )
        )
        expression = CucumberExpression.new(
            '{textAndOrNumber}',
            parameter_type_registry
        )

        class World
        end

        expect(expression.match("TLA")[0].value(World.new)).to eq(["TLA", nil])
        expect(expression.match("123")[0].value(World.new)).to eq([nil, "123"])
      end

      # Ruby specific

      it "delegates transform to custom object" do
        parameter_type_registry = ParameterTypeRegistry.new
        parameter_type_registry.define_parameter_type(
            ParameterType.new(
                'widget',
                /\w+/,
                Object,
                -> (s) {
                  self.create_widget(s)
                },
                false,
                true
            )
        )
        expression = CucumberExpression.new(
            'I have a {widget}',
            parameter_type_registry
        )

        class World
          def create_widget(s)
            "widget:#{s}"
          end
        end

        args = expression.match("I have a bolt")
        expect(args[0].value(World.new)).to eq('widget:bolt')
      end

      it "reports undefined parameter type name" do
        parameter_type_registry = ParameterTypeRegistry.new

        begin
          CucumberExpression.new(
              'I have {int} {widget}(s) in {word}',
              parameter_type_registry
          )
        rescue UndefinedParameterTypeError => e
          expect(e.undefined_parameter_type_name).to eq('widget')
        end
      end

      def match(expression, text)
        cucumber_expression = CucumberExpression.new(expression, ParameterTypeRegistry.new)
        args = cucumber_expression.match(text)
        return nil if args.nil?
        args.map { |arg| arg.value(nil) }
      end
    end
  end
end
