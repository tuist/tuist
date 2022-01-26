require 'spec_helper'
require 'protobuf/cli'

RSpec.describe ::Protobuf::CLI do

  let(:app_file) do
    File.expand_path('../../../support/test_app_file.rb', __FILE__)
  end

  let(:sock_runner) do
    runner = double("SocketRunner", :register_signals => nil)
    allow(runner).to receive(:run).and_return(::ActiveSupport::Notifications.publish("after_server_bind"))
    runner
  end

  let(:zmq_runner) do
    runner = double("ZmqRunner", :register_signals => nil)
    allow(runner).to receive(:run).and_return(::ActiveSupport::Notifications.publish("after_server_bind"))
    runner
  end

  around(:each) do |example|
    logger = ::Protobuf::Logging.logger
    example.run
    ::Protobuf::Logging.logger = logger
  end

  before(:each) do
    allow(::Protobuf::Rpc::SocketRunner).to receive(:new).and_return(sock_runner)
    allow(::Protobuf::Rpc::ZmqRunner).to receive(:new).and_return(zmq_runner)
  end

  describe '#start' do
    let(:base_args) { ['start', app_file] }
    let(:test_args) { [] }
    let(:args) { base_args + test_args }

    context 'host option' do
      let(:test_args) { ['--host=123.123.123.123'] }

      it 'sends the host option to the runner' do
        expect(::Protobuf::Rpc::SocketRunner).to receive(:new) do |options|
          expect(options[:host]).to eq '123.123.123.123'
        end.and_return(sock_runner)
        described_class.start(args)
      end
    end

    context 'port option' do
      let(:test_args) { ['--port=12345'] }

      it 'sends the port option to the runner' do
        expect(::Protobuf::Rpc::SocketRunner).to receive(:new) do |options|
          expect(options[:port]).to eq 12345
        end.and_return(sock_runner)
        described_class.start(args)
      end
    end

    context 'threads option' do
      let(:test_args) { ['--threads=500'] }

      it 'sends the threads option to the runner' do
        expect(::Protobuf::Rpc::SocketRunner).to receive(:new) do |options|
          expect(options[:threads]).to eq 500
        end.and_return(sock_runner)
        described_class.start(args)
      end
    end

    context 'backlog option' do
      let(:test_args) { ['--backlog=500'] }

      it 'sends the backlog option to the runner' do
        expect(::Protobuf::Rpc::SocketRunner).to receive(:new) do |options|
          expect(options[:backlog]).to eq 500
        end.and_return(sock_runner)
        described_class.start(args)
      end
    end

    context 'threshold option' do
      let(:test_args) { ['--threshold=500'] }

      it 'sends the backlog option to the runner' do
        expect(::Protobuf::Rpc::SocketRunner).to receive(:new) do |options|
          expect(options[:threshold]).to eq 500
        end.and_return(sock_runner)
        described_class.start(args)
      end
    end

    context 'log options' do
      let(:test_args) { ['--log=mylog.log', '--level=0'] }

      it 'sends the log file and level options to the runner' do
        expect(::Protobuf::Logging).to receive(:initialize_logger) do |file, level|
          expect(file).to eq 'mylog.log'
          expect(level).to eq 0
        end
        described_class.start(args)
      end
    end

    context 'gc options' do

      context 'when gc options are not present' do
        let(:test_args) { [] }

        it 'sets both request and serialization pausing to false' do
          described_class.start(args)
          expect(::Protobuf).to_not be_gc_pause_server_request
        end
      end

      unless defined?(JRUBY_VERSION)
        context 'request pausing' do
          let(:test_args) { ['--gc_pause_request'] }

          it 'sets the configuration option to GC pause server request' do
            described_class.start(args)
            expect(::Protobuf).to be_gc_pause_server_request
          end
        end
      end
    end

    context 'deprecation options' do
      context 'when not given' do
        let(:test_args) { [] }

        context 'when no ENV is present and no command line option' do
          before { ENV.delete("PB_IGNORE_DEPRECATIONS") }

          it 'sets the deprecation warning flag to true' do
            described_class.start(args)
            expect(::Protobuf.print_deprecation_warnings?).to be true
          end
        end

        context 'if ENV["PB_IGNORE_DEPRECATIONS"] is present' do
          before { ENV["PB_IGNORE_DEPRECATIONS"] = "1" }
          after { ENV.delete("PB_IGNORE_DEPRECATIONS") }

          it 'sets the deprecation warning flag to false ' do
            described_class.start(args)
            expect(::Protobuf.print_deprecation_warnings?).to be false
          end
        end
      end

      context 'when enabled' do
        let(:test_args) { ['--print_deprecation_warnings'] }

        it 'sets the deprecation warning flag to true' do
          described_class.start(args)
          expect(::Protobuf.print_deprecation_warnings?).to be true
        end
      end

      context 'when disabled' do
        let(:test_args) { ['--no-print_deprecation_warnings'] }

        it 'sets the deprecation warning flag to false' do
          described_class.start(args)
          expect(::Protobuf.print_deprecation_warnings?).to be false
        end
      end
    end

    context 'run modes' do

      context "extension" do
        let(:runner) { ::Protobuf::Rpc::Servers::SocketRunner }

        it "loads the runner specified by PB_SERVER_TYPE" do
          ENV['PB_SERVER_TYPE'] = "protobuf/rpc/servers/socket_runner"
          expect(runner).to receive(:new).and_return(sock_runner)
          described_class.start(args)
          ENV.delete('PB_SERVER_TYPE')
        end

        context "without extension loaded" do
          it "will throw a LoadError when extension is not loaded" do
            ENV['PB_SERVER_TYPE'] = "socket_to_load"
            expect { described_class.start(args) }.to raise_error(LoadError, /socket_to_load/)
            ENV.delete("PB_SERVER_TYPE")
          end
        end
      end

      context 'socket' do
        let(:test_args) { ['--socket'] }
        let(:runner) { ::Protobuf::Rpc::SocketRunner }

        before do
          expect(::Protobuf::Rpc::ZmqRunner).not_to receive(:new)
        end

        it 'is activated by the --socket switch' do
          expect(runner).to receive(:new)
          described_class.start(args)
        end

        it 'is activated by PB_SERVER_TYPE=Socket ENV variable' do
          ENV['PB_SERVER_TYPE'] = "Socket"
          expect(runner).to receive(:new).and_return(sock_runner)
          described_class.start(args)
          ENV.delete('PB_SERVER_TYPE')
        end
      end

      context 'zmq workers only' do
        let(:test_args) { ['--workers_only', '--zmq'] }
        let(:runner) { ::Protobuf::Rpc::ZmqRunner }

        before do
          expect(::Protobuf::Rpc::SocketRunner).not_to receive(:new)
        end

        it 'is activated by the --workers_only switch' do
          expect(runner).to receive(:new) do |options|
            expect(options[:workers_only]).to be true
          end.and_return(zmq_runner)

          described_class.start(args)
        end

        it 'is activated by PB_WORKERS_ONLY=1 ENV variable' do
          ENV['PB_WORKERS_ONLY'] = "1"
          expect(runner).to receive(:new) do |options|
            expect(options[:workers_only]).to be true
          end.and_return(zmq_runner)

          described_class.start(args)
          ENV.delete('PB_WORKERS_ONLY')
        end
      end

      context 'zmq worker port' do
        let(:test_args) { ['--worker_port=1234', '--zmq'] }
        let(:runner) { ::Protobuf::Rpc::ZmqRunner }

        before do
          expect(::Protobuf::Rpc::SocketRunner).not_to receive(:new)
        end

        it 'is activated by the --worker_port switch' do
          expect(runner).to receive(:new) do |options|
            expect(options[:worker_port]).to eq(1234)
          end.and_return(zmq_runner)

          described_class.start(args)
        end
      end

      context 'zmq' do
        let(:test_args) { ['--zmq'] }
        let(:runner) { ::Protobuf::Rpc::ZmqRunner }

        before do
          expect(::Protobuf::Rpc::SocketRunner).not_to receive(:new)
        end

        it 'is activated by the --zmq switch' do
          expect(runner).to receive(:new)
          described_class.start(args)
        end

        it 'is activated by PB_SERVER_TYPE=Zmq ENV variable' do
          ENV['PB_SERVER_TYPE'] = "Zmq"
          expect(runner).to receive(:new)
          described_class.start(args)
          ENV.delete('PB_SERVER_TYPE')
        end
      end

      context 'after server bind' do
        let(:sock_runner) { double("FakeRunner", :run => nil) }

        before { allow(sock_runner).to receive(:run).and_yield }

        it 'publishes when using the lib/protobuf callback' do
          message_after_bind = false
          ::Protobuf.after_server_bind do
            message_after_bind = true
          end
          described_class.start(args)
          expect(message_after_bind).to eq(true)
        end
      end

      context 'before server bind' do
        it 'publishes a message before the runner runs' do
          message_before_bind = false
          ::ActiveSupport::Notifications.subscribe('before_server_bind') do
            message_before_bind = true
          end
          described_class.start(args)
          expect(message_before_bind).to eq(true)
        end

        it 'publishes when using the lib/protobuf callback' do
          message_before_bind = false
          ::Protobuf.before_server_bind do
            message_before_bind = true
          end
          described_class.start(args)
          expect(message_before_bind).to eq(true)
        end
      end

    end

  end

end
