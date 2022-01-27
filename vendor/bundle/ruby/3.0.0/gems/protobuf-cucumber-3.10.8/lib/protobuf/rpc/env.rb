module Protobuf
  module Rpc
    class Env < Hash
      # Creates an accessor that simply sets and reads a key in the hash:
      #
      #   class Config < Hash
      #     hash_accessor :app
      #   end
      #
      #   config = Config.new
      #   config.app = Foo
      #   config[:app] #=> Foo
      #
      #   config[:app] = Bar
      #   config.app #=> Bar
      #
      def self.hash_accessor(*names) #:nodoc:
        names.each do |name|
          name_str = name.to_s.freeze

          define_method name do
            self[name_str]
          end

          define_method "#{name}=" do |value|
            self[name_str] = value
          end

          define_method "#{name}?" do
            !self[name_str].nil?
          end
        end
      end

      # TODO: Add extra info about the environment (i.e. variables) and other
      # information that might be useful
      hash_accessor :client_host,
                    :encoded_request,
                    :encoded_response,
                    :log_signature,
                    :method_name,
                    :request,
                    :request_type,
                    :request_wrapper,
                    :response,
                    :response_type,
                    :rpc_method,
                    :rpc_service,
                    :server,
                    :service_name,
                    :worker_id

      def initialize(options = {})
        merge!(options)

        self['worker_id'] = ::Thread.current.object_id.to_s(16)
      end
    end
  end
end
