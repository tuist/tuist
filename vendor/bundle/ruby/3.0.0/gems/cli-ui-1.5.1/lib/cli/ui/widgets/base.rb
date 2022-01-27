require('cli/ui')

module CLI
  module UI
    module Widgets
      class Base
        def self.call(argstring)
          new(argstring).render
        end

        def initialize(argstring)
          pat = self.class.argparse_pattern
          unless (@match_data = pat.match(argstring))
            raise(Widgets::InvalidWidgetArguments.new(argstring, pat))
          end
          @match_data.names.each do |name|
            instance_variable_set(:"@#{name}", @match_data[name])
          end
        end

        def self.argparse_pattern
          const_get(:ARGPARSE_PATTERN)
        end
      end
    end
  end
end
