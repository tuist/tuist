# frozen_string_literal: true

module Cucumber
  module Gherkin
    module I18n
      class << self
        def code_keyword_for(gherkin_keyword)
          gherkin_keyword.gsub(/[\s',!]/, '').strip
        end

        def code_keywords_for(gherkin_keywords)
          gherkin_keywords.reject { |kw| kw == '* ' }.map { |kw| code_keyword_for(kw) }
        end
      end
    end
  end
end
