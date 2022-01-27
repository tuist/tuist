module Mocha
  module Integration
    module TestUnit
      module Nothing
        def self.applicable_to?(_test_unit_version, _ruby_version = nil)
          true
        end

        def self.description
          'nothing (no Test::Unit integration available)'
        end

        def self.included(_mod)
          raise 'No Test::Unit integration available'
        end
      end
    end
  end
end
