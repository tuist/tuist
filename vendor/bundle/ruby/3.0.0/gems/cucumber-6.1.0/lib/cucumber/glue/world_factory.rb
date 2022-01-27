module Cucumber
  module Glue
    class WorldFactory
      def initialize(proc)
        @proc = proc || -> { Object.new }
      end

      def create_world
        @proc.call || raise_nil_world
      end

      def raise_nil_world
        raise NilWorld
      rescue NilWorld => e
        e.backtrace.clear
        e.backtrace.push(Glue.backtrace_line(@proc, 'World'))
        raise e
      end
    end
  end
end
