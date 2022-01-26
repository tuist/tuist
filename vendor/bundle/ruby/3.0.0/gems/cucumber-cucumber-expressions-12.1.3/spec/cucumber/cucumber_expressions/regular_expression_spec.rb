require 'cucumber/cucumber_expressions/regular_expression'
require 'cucumber/cucumber_expressions/parameter_type_registry'

module Cucumber
  module CucumberExpressions
    describe RegularExpression do
      it "documents match arguments" do
        parameter_type_registry = ParameterTypeRegistry.new

        ### [capture-match-arguments]
        expr = /I have (\d+) cukes? in my (\w*) now/
        expression = RegularExpression.new(expr, parameter_type_registry)
        args = expression.match("I have 7 cukes in my belly now")
        expect( args[0].value(nil) ).to eq(7)
        expect( args[1].value(nil) ).to eq("belly")
        ### [capture-match-arguments]
      end

      it "does no transform by default" do
        expect( match(/(\d\d)/, "22") ).to eq(["22"])
      end

      it "does not transform anonymous" do
        expect( match(/(.*)/, "22") ).to eq(["22"])
      end

      it "transforms negative int" do
        expect( match(/(-?\d+)/, "-22") ).to eq([-22])
      end

      it "transforms positive int" do
        expect( match(/(\d+)/, "22") ).to eq([22])
      end

      it "returns nil when there is no match" do
        expect( match(/hello/, "world") ).to be_nil
      end

      it "matches nested capture group without match" do
        expect( match(/^a user( named "([^"]*)")?$/, 'a user') ).to eq([nil])
      end

      it "matches nested capture group with match" do
        expect( match(/^a user( named "([^"]*)")?$/, 'a user named "Charlie"') ).to eq(['Charlie'])
      end

      it "ignores non capturing groups" do
        expect( match(
          /(\S+) ?(can|cannot) (?:delete|cancel) the (\d+)(?:st|nd|rd|th) (attachment|slide) ?(?:upload)?/,
          "I can cancel the 1st slide upload")
        ).to eq(["I", "can", 1, "slide"])
      end

      it "matches capture group nested in optional one" do
        regexp = /^a (pre-commercial transaction |pre buyer fee model )?purchase(?: for \$(\d+))?$/
        expect( match(regexp, 'a purchase') ).to eq([nil, nil])
        expect( match(regexp, 'a purchase for $33') ).to eq([nil, 33])
        expect( match(regexp, 'a pre buyer fee model purchase') ).to eq(['pre buyer fee model ', nil])
      end

      it "works with escaped parenthesis" do
        expect( match(/Across the line\(s\)/, 'Across the line(s)') ).to eq([])
      end

      it "exposes source and regexp" do
        regexp = /I have (\d+) cukes? in my (\+) now/
        expression = RegularExpression.new(regexp, ParameterTypeRegistry.new)
        expect(expression.regexp).to eq(regexp)
        expect(expression.source).to eq(regexp.source)
      end

      def match(expression, text)
        regular_expression = RegularExpression.new(expression, ParameterTypeRegistry.new)
        arguments = regular_expression.match(text)
        return nil if arguments.nil?
        arguments.map { |arg| arg.value(nil) }
      end
    end
  end
end
