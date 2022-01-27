# frozen_string_literal: true

require 'gherkin'
require 'gherkin/dialect'

module Cucumber
  module Gherkin
    class StepsParser
      def initialize(builder, language)
        @builder = builder
        @language = language
      end

      def parse(text)
        dialect = ::Gherkin::Dialect.for(@language)
        gherkin_document = nil
        messages = ::Gherkin.from_source('dummy', feature_header(dialect) + text, gherkin_options)

        messages.each do |message|
          gherkin_document = message.gherkin_document.to_hash unless message.gherkin_document.nil?
        end

        @builder.steps(gherkin_document[:feature][:children][0][:scenario][:steps])
      end

      def gherkin_options
        {
          default_dialect: @language,
          include_source: false,
          include_gherkin_document: true,
          include_pickles: false
        }
      end

      def feature_header(dialect)
        %(#{dialect.feature_keywords[0]}:
            #{dialect.scenario_keywords[0]}:
         )
      end
    end
  end
end
