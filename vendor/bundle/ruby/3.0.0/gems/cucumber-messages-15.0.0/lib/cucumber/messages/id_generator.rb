require 'securerandom'

module Cucumber
  module Messages
    module IdGenerator
      class Incrementing
        def initialize
          @index = -1
        end

        def new_id
          @index += 1
          @index.to_s
        end
      end

      class UUID
        def new_id
          SecureRandom.uuid
        end
      end
    end
  end
end
