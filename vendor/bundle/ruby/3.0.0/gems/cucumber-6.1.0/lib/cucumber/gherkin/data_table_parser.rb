# frozen_string_literal: true

require 'gherkin'
require 'gherkin/dialect'

module Cucumber
  module Gherkin
    class DataTableParser
      def initialize(builder)
        @builder = builder
      end

      def parse(text)
        gherkin_document = nil
        messages = ::Gherkin.from_source('dummy', feature_header + text, gherkin_options)

        messages.each do |message|
          gherkin_document = message.gherkin_document.to_hash unless message.gherkin_document.nil?
        end

        return if gherkin_document.nil?
        gherkin_document[:feature][:children][0][:scenario][:steps][0][:data_table][:rows].each do |row|
          @builder.row(row[:cells].map { |cell| cell[:value] })
        end
      end

      def gherkin_options
        {
          include_source: false,
          include_gherkin_document: true,
          include_pickles: false
        }
      end

      def feature_header
        dialect = ::Gherkin::Dialect.for('en')
        %(#{dialect.feature_keywords[0]}:
            #{dialect.scenario_keywords[0]}:
              #{dialect.given_keywords[0]} x
         )
      end
    end
  end
end
