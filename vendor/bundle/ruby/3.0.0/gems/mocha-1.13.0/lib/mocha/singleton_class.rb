if Gem::Version.new(RUBY_VERSION.dup) < Gem::Version.new('1.9.2')
  unless Kernel.method_defined?(:singleton_class)
    module Kernel
      def singleton_class
        class << self; self; end
      end
    end
  end
end
