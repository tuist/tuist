# frozen_string_literal: true

module ActionView
  module Helpers
    module Tags # :nodoc:
      class DateField < DatetimeField # :nodoc:
        private
          def format_date(value)
            value&.strftime("%Y-%m-%d")
          end
      end
    end
  end
end
