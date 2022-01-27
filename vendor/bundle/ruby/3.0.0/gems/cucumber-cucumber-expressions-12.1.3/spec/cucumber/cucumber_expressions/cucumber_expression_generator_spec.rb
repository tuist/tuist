require 'cucumber/cucumber_expressions/cucumber_expression_generator'
require 'cucumber/cucumber_expressions/cucumber_expression'
require 'cucumber/cucumber_expressions/parameter_type'
require 'cucumber/cucumber_expressions/parameter_type_registry'

module Cucumber
  module CucumberExpressions
    describe CucumberExpressionGenerator do
      class Currency
      end

      before do
        @parameter_type_registry = ParameterTypeRegistry.new
        @generator = CucumberExpressionGenerator.new(@parameter_type_registry)
      end

      it "documents expression generation" do
        parameter_registry = ParameterTypeRegistry.new
        ### [generate-expression]
        generator = CucumberExpressionGenerator.new(parameter_registry)
        undefined_step_text = "I have 2 cucumbers and 1.5 tomato"
        generated_expression = generator.generate_expression(undefined_step_text)
        expect(generated_expression.source).to eq("I have {int} cucumbers and {float} tomato")
        expect(generated_expression.parameter_types[1].type).to eq(Float)
        ### [generate-expression]
      end

      it "generates expression for no args" do
        assert_expression("hello", [], "hello")
      end

      it "generates expression with escaped left parenthesis" do
        assert_expression(
          "\\(iii)", [],
          "(iii)")
      end

      it "generates expression with escaped left curly brace" do
        assert_expression(
          "\\{iii}", [],
          "{iii}")
      end

      it "generates expression with escaped slashes" do
        assert_expression(
          "The {int}\\/{int}\\/{int} hey", ["int", "int2", "int3"],
          "The 1814/05/17 hey")
      end

      it "generates expression for int float arg" do
        assert_expression(
          "I have {int} cukes and {float} euro", ["int", "float"],
          "I have 2 cukes and 1.5 euro")
      end

      it "generates expression for strings" do
        assert_expression(
            "I like {string} and {string}", ["string", "string2"],
            'I like "bangers" and \'mash\'')
      end

      it "generates expression with % sign" do
        assert_expression(
            "I am {int}% foobar", ["int"],
            'I am 20% foobar')
      end

      it "generates expression for just int" do
        assert_expression(
          "{int}", ["int"],
          "99999")
      end

      it "numbers only second argument when builtin type is not reserved keyword" do
        assert_expression(
          "I have {int} cukes and {int} euro", ["int", "int2"],
          "I have 2 cukes and 5 euro")
      end

      it "numbers only second argument when type is not reserved keyword" do
        @parameter_type_registry.define_parameter_type(ParameterType.new(
          'currency',
          '[A-Z]{3}',
          Currency,
          lambda {|s| Currency.new(s)},
          true,
          true
        ))

        assert_expression(
          "I have a {currency} account and a {currency} account", ["currency", "currency2"],
          "I have a EUR account and a GBP account")
      end

      it "exposes parameters in generated expression" do
        expression = @generator.generate_expression("I have 2 cukes and 1.5 euro")
        types = expression.parameter_types.map(&:type)
        expect(types).to eq([Integer, Float])
      end

      it "matches parameter types with optional capture groups" do
        @parameter_type_registry.define_parameter_type(ParameterType.new(
            'optional-flight',
            /(1st flight)?/,
            String,
            lambda {|s| s},
            true,
            false
        ))
        @parameter_type_registry.define_parameter_type(ParameterType.new(
            'optional-hotel',
            /(1 hotel)?/,
            String,
            lambda {|s| s},
            true,
            false
        ))

        expression = @generator.generate_expressions("I reach Stage 4: 1st flight -1 hotel")[0]
        # While you would expect this to be `I reach Stage {int}: {optional-flight} -{optional-hotel}`
        # the `-1` causes {int} to match just before {optional-hotel}.
        expect(expression.source).to eq("I reach Stage {int}: {optional-flight} {int} hotel")
      end

      it "generates at most 256 expressions" do
        for i in 0..3
          @parameter_type_registry.define_parameter_type(ParameterType.new(
              "my-type-#{i}",
              /([a-z] )*?[a-z]/,
              String,
              lambda {|s| s},
              true,
              false
          ))
        end
        # This would otherwise generate 4^11=4194300 expressions and consume just shy of 1.5GB.
        expressions = @generator.generate_expressions("a s i m p l e s t e p")
        expect(expressions.length).to eq(256)
      end

      it "prefers expression with longest non empty match" do
        @parameter_type_registry.define_parameter_type(ParameterType.new(
            'zero-or-more',
            /[a-z]*/,
            String,
            lambda {|s| s},
            true,
            false
        ))
        @parameter_type_registry.define_parameter_type(ParameterType.new(
            'exactly-one',
            /[a-z]/,
            String,
            lambda {|s| s},
            true,
            false
        ))

        expressions = @generator.generate_expressions("a simple step")
        expect(expressions.length).to eq(2)
        expect(expressions[0].source).to eq("{exactly-one} {zero-or-more} {zero-or-more}")
        expect(expressions[1].source).to eq("{zero-or-more} {zero-or-more} {zero-or-more}")
      end

      context "does not suggest parameter when match is" do
        before do
          @parameter_type_registry.define_parameter_type(ParameterType.new(
              'direction',
              /(up|down)/,
              String,
              lambda {|s| s},
              true,
              false
          ))
        end

        it "at the beginning of a word" do
          expect(@generator.generate_expression("When I download a picture").source).not_to eq("When I {direction}load a picture")
          expect(@generator.generate_expression("When I download a picture").source).to eq("When I download a picture")
        end

        it "inside a word" do
          expect(@generator.generate_expression("When I watch the muppet show").source).not_to eq("When I watch the m{direction}pet show")
          expect(@generator.generate_expression("When I watch the muppet show").source).to eq("When I watch the muppet show")
        end

        it "at the end of a word" do
          expect(@generator.generate_expression("When I create a group").source).not_to eq("When I create a gro{direction}")
          expect(@generator.generate_expression("When I create a group").source).to eq("When I create a group")
        end
      end

      context "does suggest parameter when match is" do
        before do
          @parameter_type_registry.define_parameter_type(ParameterType.new(
              'direction',
              /(up|down)/,
              String,
              lambda {|s| s},
              true,
              false
          ))
        end

        it "a full word" do
          expect(@generator.generate_expression("When I go down the road").source).to eq("When I go {direction} the road")
          expect(@generator.generate_expression("When I walk up the hill").source).to eq("When I walk {direction} the hill")
          expect(@generator.generate_expression("up the hill, the road goes down").source).to eq("{direction} the hill, the road goes {direction}")
        end

        it 'wrapped around punctuation characters' do
          expect(@generator.generate_expression("When direction is:down").source).to eq("When direction is:{direction}")
          expect(@generator.generate_expression("Then direction is down.").source).to eq("Then direction is {direction}.")
        end
      end

      def assert_expression(expected_expression, expected_argument_names, text)
        generated_expression = @generator.generate_expression(text)
        expect(generated_expression.parameter_names).to eq(expected_argument_names)
        expect(generated_expression.source).to eq(expected_expression)

        cucumber_expression = CucumberExpression.new(generated_expression.source, @parameter_type_registry)
        match = cucumber_expression.match(text)
        if match.nil?
          raise "Expected text '#{text}' to match generated expression '#{generated_expression.source}'"
        end
        expect(match.length).to eq(expected_argument_names.length)
      end
    end
  end
end
