require 'cucumber/wire/connection'
require 'cucumber/wire/configuration'

module Cucumber
  module Wire
    describe Connection do
      class TestConnection < Connection
        attr_accessor :socket
      end

      class TestConfiguration
        attr_reader :custom_timeout

        def initialize
          @custom_timeout = {}
        end

        def timeout(message = nil)
          return :default_timeout if message.nil?
          @custom_timeout[message] || Configuration::DEFAULT_TIMEOUTS.fetch(message)
        end

        def host
          'localhost'
        end

        def port
          '3902'
        end
      end

      before(:each) do
        @config = TestConfiguration.new
        @connection = TestConnection.new(@config)
        @connection.socket = @socket = double('socket').as_null_object
        @response = %q{["response"]}
      end

      it "re-raises a timeout error" do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error.new(''))
        expect(-> { @connection.call_remote(nil, :foo, []) }).to raise_error(Timeout::Error)
      end

      it "ignores timeout errors when configured to do so" do
        @config.custom_timeout[:foo] = :never

        allow(@socket).to receive(:gets) { @response }

        handler = double(:handle_response => :response)

        expect(@connection.call_remote(handler, :foo, [])).to eq :response
      end

      it "raises an exception on remote connection closed" do
        @config.custom_timeout[:foo] = :never

        allow(@socket).to receive(:gets)
        expect(-> {
          @connection.call_remote(nil, :foo, [])
        }).to raise_error(Wire::Exception, 'Remote Socket with localhost:3902 closed.')
      end
    end
  end
end
