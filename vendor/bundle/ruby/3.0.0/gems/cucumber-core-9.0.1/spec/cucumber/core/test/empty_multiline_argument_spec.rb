# frozen_string_literal: true
require 'cucumber/core/test/location'
require 'cucumber/core/test/empty_multiline_argument'

module Cucumber
  module Core
    module Test
      describe EmptyMultilineArgument do

        let(:location) { double }
        let(:arg) { EmptyMultilineArgument.new }

        describe "#data_table?" do
          it "returns false" do
            expect(arg).not_to be_data_table
          end
        end

        describe "#doc_string" do
          it "returns false" do
            expect(arg).not_to be_doc_string
          end
        end

      end
    end
  end
end
