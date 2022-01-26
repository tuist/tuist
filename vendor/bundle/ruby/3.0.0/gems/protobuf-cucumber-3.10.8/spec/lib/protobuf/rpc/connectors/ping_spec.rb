require "spec_helper"
require "protobuf/zmq"

::RSpec.describe ::Protobuf::Rpc::Connectors::Ping do
  subject { described_class.new("google.com", 80) }

  let(:host) { "google.com" }
  let(:port) { 80 }

  describe ".new" do
    it "assigns host" do
      expect(subject.host).to eq(host)
    end

    it "assigns port" do
      expect(subject.port).to eq(port)
    end
  end

  describe "#online?" do
    it "closes the socket" do
      socket = double(:close => nil, :setsockopt => nil)
      allow(subject).to receive(:tcp_socket).and_return(socket)
      expect(socket).to receive(:close)
      expect(subject).to be_online
    end

    context "when a socket can connect" do
      let(:socket) { double(:close => nil, :setsockopt => nil) }
      before { allow(subject).to receive(:tcp_socket).and_return(socket) }

      it "returns true" do
        expect(subject).to be_online
      end
    end

    context "when a socket error is raised" do
      before { allow(subject).to receive(:tcp_socket).and_raise(::Errno::ECONNREFUSED) }

      it "returns false" do
        expect(subject).to_not be_online
      end
    end

    context "when a select timeout is fired" do
      let(:wait_writable_class) { ::Class.new(StandardError) { include ::IO::WaitWritable } }
      before { expect_any_instance_of(::Socket).to receive(:connect_nonblock).and_raise(wait_writable_class) }

      it "returns false" do
        expect(::IO).to receive(:select).and_return(false)
        expect(subject).to_not be_online
      end
    end
  end

  describe "#timeout" do
    it "uses the default value" do
      expect(subject.timeout).to eq(0.2)
    end

    context "when environment variable is set" do
      before { ::ENV["PB_RPC_PING_PORT_TIMEOUT"] = "100" }

      it "uses the environmet variable" do
        expect(subject.timeout).to eq(0.1)
      end
    end
  end
end
