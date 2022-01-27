module Mocha
  module Integration
    module MiniTest
      module Nothing
        def self.applicable_to?(_test_unit_version, _ruby_version = nil)
          true
        end

        def self.description
          'nothing (no MiniTest integration available)'
        end

        def self.included(_mod)
          raise 'No MiniTest integration available'
        end
      end
    end
  end
end
