require 'cli/kit'

module CLI
  module Kit
    module Autocall
      def autocall(const, &block)
        @autocalls ||= {}
        @autocalls[const] = block
      end

      def const_missing(const)
        block = begin
          @autocalls.fetch(const)
        rescue KeyError
          return super
        end
        const_set(const, block.call)
      end
    end
  end
end
