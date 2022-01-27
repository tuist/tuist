require 'cucumber/cucumber_expressions/cucumber_expression'
require 'cucumber/cucumber_expressions/regular_expression'
require 'cucumber/cucumber_expressions/parameter_type_registry'

module Cucumber
  module CucumberExpressions
    class Color
      attr_reader :name

      ### [color-constructor]
      def initialize(name)
        @name = name
      end

      ### [color-constructor]

      def ==(other)
        other.is_a?(Color) && other.name == name
      end
    end

    class CssColor
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def ==(other)
        other.is_a?(CssColor) && other.name == name
      end
    end

    class Coordinate
      attr_reader :x, :y, :z

      def initialize(x, y, z)
        @x, @y, @z = x, y, z
      end

      def ==(other)
        other.is_a?(Coordinate) && other.x == x && other.y == y && other.z == z
      end
    end

    describe "Custom parameter type" do
      before do
        parameter_type_registry = ParameterTypeRegistry.new
        ### [add-color-parameter-type]
        parameter_type_registry.define_parameter_type(ParameterType.new(
            'color',                   # name
            /red|blue|yellow/,         # regexp
            Color,                     # type
            lambda {|s| Color.new(s)}, # transform
            true,                      # use_for_snippets
            false                      # prefer_for_regexp_match
        ))
        ### [add-color-parameter-type]
        @parameter_type_registry = parameter_type_registry
      end

      it "throws exception for illegal character in parameter name" do
        expect do
          ParameterType.new(
              '[string]',
              /.*/,
              String,
              lambda {|s| s},
              true,
              false
          )
        end.to raise_error("Illegal character in parameter name {[string]}. Parameter names may not contain '[]()$.|?*+'")
      end

      describe CucumberExpression do
        it "matches parameters with custom parameter type" do
          expression = CucumberExpression.new("I have a {color} ball", @parameter_type_registry)
          transformed_argument_value = expression.match("I have a red ball")[0].value(nil)
          expect(transformed_argument_value).to eq(Color.new('red'))
        end

        it "matches parameters with multiple capture groups" do
          @parameter_type_registry.define_parameter_type(ParameterType.new(
              'coordinate',
              /(\d+),\s*(\d+),\s*(\d+)/,
              Coordinate,
              lambda {|x, y, z| Coordinate.new(x.to_i, y.to_i, z.to_i)},
              true,
              false
          ))

          expression = CucumberExpression.new(
              'A {int} thick line from {coordinate} to {coordinate}',
              @parameter_type_registry
          )
          args = expression.match('A 5 thick line from 10,20,30 to 40,50,60')

          thick = args[0].value(nil)
          expect(thick).to eq(5)

          from = args[1].value(nil)
          expect(from).to eq(Coordinate.new(10, 20, 30))

          to = args[2].value(nil)
          expect(to).to eq(Coordinate.new(40, 50, 60))
        end

        it "matches parameters with custom parameter type using optional capture group" do
          parameter_type_registry = ParameterTypeRegistry.new
          parameter_type_registry.define_parameter_type(ParameterType.new(
              'color',
              [/red|blue|yellow/, /(?:dark|light) (?:red|blue|yellow)/],
              Color,
              lambda {|s| Color.new(s)},
              true,
              false
          ))
          expression = CucumberExpression.new("I have a {color} ball", parameter_type_registry)
          transformed_argument_value = expression.match("I have a dark red ball")[0].value(nil)
          expect(transformed_argument_value).to eq(Color.new('dark red'))
        end

        it "defers transformation until queried from argument" do
          @parameter_type_registry.define_parameter_type(ParameterType.new(
              'throwing',
              /bad/,
              CssColor,
              lambda {|s| raise "Can't transform [#{s}]"},
              true,
              false
          ))
          expression = CucumberExpression.new("I have a {throwing} parameter", @parameter_type_registry)
          args = expression.match("I have a bad parameter")
          expect {args[0].value(nil)}.to raise_error("Can't transform [bad]")
        end

        describe "conflicting parameter type" do
          it "is detected for type name" do
            expect {
              @parameter_type_registry.define_parameter_type(ParameterType.new(
                  'color',
                  /.*/,
                  CssColor,
                  lambda {|s| CssColor.new(s)},
                  true,
                  false
              ))
            }.to raise_error("There is already a parameter with name color")
          end

          it "is not detected for type" do
            @parameter_type_registry.define_parameter_type(ParameterType.new(
                'whatever',
                /.*/,
                Color,
                lambda {|s| Color.new(s)},
                false,
                false
            ))
          end

          it "is not detected for regexp" do
            @parameter_type_registry.define_parameter_type(ParameterType.new(
                'css-color',
                /red|blue|yellow/,
                CssColor,
                lambda {|s| CssColor.new(s)},
                true,
                false
            ))

            css_color = CucumberExpression.new("I have a {css-color} ball", @parameter_type_registry)
            css_color_value = css_color.match("I have a blue ball")[0].value(nil)
            expect(css_color_value).to eq(CssColor.new("blue"))

            color = CucumberExpression.new("I have a {color} ball", @parameter_type_registry)
            color_value = color.match("I have a blue ball")[0].value(nil)
            expect(color_value).to eq(Color.new("blue"))
          end
        end
      end

      describe RegularExpression do
        it "matches arguments with custom parameter type without name" do
          parameter_type_registry = ParameterTypeRegistry.new
          parameter_type_registry.define_parameter_type(ParameterType.new(
              nil,
              /red|blue|yellow/,
              Color,
              lambda {|s| Color.new(s)},
              true,
              false
          ))

          expression = RegularExpression.new(/I have a (red|blue|yellow) ball/, parameter_type_registry)
          value = expression.match("I have a red ball")[0].value(nil)
          expect(value).to eq(Color.new('red'))
        end
      end
    end
  end
end
