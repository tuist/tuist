require 'json'

module Cucumber
  module Messages
    module WriteNdjson
      def write_ndjson_to(io)
        io.write(self.to_json(proto3: true))
        io.write("\n")
      end
    end
  end
end
