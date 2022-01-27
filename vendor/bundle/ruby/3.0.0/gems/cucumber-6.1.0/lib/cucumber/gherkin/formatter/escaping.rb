# frozen_string_literal: true

module Cucumber
  module Gherkin
    module Formatter
      module Escaping
        # Escapes a pipes and backslashes:
        #
        # * | becomes \|
        # * \ becomes \\
        #
        # This is used in the pretty formatter.
        def escape_cell(sym)
          sym.gsub(/\\(?!\|)/, '\\\\\\\\').gsub(/\n/, '\\n').gsub(/\|/, '\\|')
        end
      end
    end
  end
end
