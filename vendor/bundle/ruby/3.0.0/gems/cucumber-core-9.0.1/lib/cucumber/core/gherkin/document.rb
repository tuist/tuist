# frozen_string_literal: true

module Cucumber
  module Core
    module Gherkin
      class Document
        attr_reader :uri, :body, :language

        def initialize(uri, body, language=nil)
          @uri      = uri
          @body     = body
          @language = language || 'en'
        end

        def to_s
          body
        end

        def ==(other)
          to_s == other.to_s
        end
      end
    end
  end
end
