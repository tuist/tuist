require 'spec_helper'

require 'protobuf/rpc/service_directory'

RSpec.describe ::Protobuf::Rpc::ServiceDirectory do
  subject { described_class.instance }

  let(:echo_server) do
    ::Protobuf::Rpc::DynamicDiscovery::Server.new(
      :uuid => 'echo',
      :address => '127.0.0.1',
      :port => '1111',
      :ttl => 10,
      :services => %w(EchoService),
    )
  end

  let(:hello_server) do
    ::Protobuf::Rpc::DynamicDiscovery::Server.new(
      :uuid => "hello",
      :address => '127.0.0.1',
      :port => "1112",
      :ttl => 10,
      :services => %w(HelloService),
    )
  end

  let(:hello_server_with_short_ttl) do
    ::Protobuf::Rpc::DynamicDiscovery::Server.new(
      :uuid => "hello_server_with_short_ttl",
      :address => '127.0.0.1',
      :port => '1113',
      :ttl => 1,
      :services => %w(HelloService),
    )
  end

  let(:combo_server) do
    ::Protobuf::Rpc::DynamicDiscovery::Server.new(
      :uuid => "combo",
      :address => '127.0.0.1',
      :port => '1114',
      :ttl => 10,
      :services => %w(HelloService EchoService),
    )
  end

  before(:all) do
    @address = "127.0.0.1"
    @port = 33333
    @socket = UDPSocket.new
    EchoService = Class.new

    described_class.address = @address
    described_class.port = @port
  end

  def expect_event_trigger(event)
    expect(::ActiveSupport::Notifications).to receive(:instrument)
      .with(event, hash_including(:listing => an_instance_of(::Protobuf::Rpc::ServiceDirectory::Listing))).once
  end

  def send_beacon(type, server)
    type = type.to_s.upcase
    beacon = ::Protobuf::Rpc::DynamicDiscovery::Beacon.new(
      :server => server,
      :beacon_type => ::Protobuf::Rpc::DynamicDiscovery::BeaconType.fetch(type),
    )

    @socket.send(beacon.encode, 0, @address, @port)
    sleep 0.01 # give the service directory time to process the beacon
  end

  it "should be a singleton" do
    expect(subject).to be_a_kind_of(Singleton)
  end

  it "should be configured to listen to address 127.0.0.1" do
    expect(described_class.address).to eq '127.0.0.1'
  end

  it "should be configured to listen to port 33333" do
    expect(described_class.port).to eq 33333
  end

  it "should defer .start to the instance#start" do
    expect(described_class.instance).to receive(:start)
    described_class.start
  end

  it "should yeild itself to blocks passed to .start" do
    allow(described_class.instance).to receive(:start)
    expect { |b| described_class.start(&b) }.to yield_with_args(described_class)
  end

  it "should defer .stop to the instance#stop" do
    expect(described_class.instance).to receive(:stop)
    described_class.stop
  end

  context "stopped" do
    before { subject.stop }

    describe "#lookup" do
      it "should return nil" do
        send_beacon(:heartbeat, echo_server)
        expect(subject.lookup("EchoService")).to be_nil
      end
    end

    describe "#restart" do
      it "should start the service" do
        subject.restart
        expect(subject).to be_running
      end
    end

    describe "#running" do
      it "should be false" do
        expect(subject).to_not be_running
      end
    end

    describe "#stop" do
      it "has no effect" do
        subject.stop
      end
    end
  end

  context "started" do
    before { subject.start }
    after { subject.stop }

    specify { expect(subject).to be_running }

    it "should trigger added events" do
      expect_event_trigger("directory.listing.added")
      send_beacon(:heartbeat, echo_server)
    end

    it "should trigger updated events" do
      send_beacon(:heartbeat, echo_server)
      expect_event_trigger("directory.listing.updated")
      send_beacon(:heartbeat, echo_server)
    end

    it "should trigger removed events" do
      send_beacon(:heartbeat, echo_server)
      expect_event_trigger("directory.listing.removed")
      send_beacon(:flatline, echo_server)
    end

    describe "#all_listings_for" do
      context "when listings are present" do
        it "returns all listings for a given service" do
          send_beacon(:heartbeat, hello_server)
          send_beacon(:heartbeat, combo_server)

          expect(subject.all_listings_for("HelloService").size).to eq(2)
        end
      end

      context "when no listings are present" do
        it "returns and empty array" do
          expect(subject.all_listings_for("HelloService").size).to eq(0)
        end
      end
    end

    describe "#each_listing" do
      it "should yield to a block for each listing" do
        send_beacon(:heartbeat, hello_server)
        send_beacon(:heartbeat, echo_server)
        send_beacon(:heartbeat, combo_server)

        expect do |block|
          subject.each_listing(&block)
        end.to yield_control.exactly(3).times
      end
    end

    describe "#lookup" do
      it "should provide listings by service" do
        send_beacon(:heartbeat, hello_server)
        expect(subject.lookup("HelloService").to_hash).to eq hello_server.to_hash
      end

      it "should return random listings" do
        send_beacon(:heartbeat, hello_server)
        send_beacon(:heartbeat, combo_server)

        uuids = 100.times.map { subject.lookup("HelloService").uuid }
        expect(uuids.count("hello")).to be_within(25).of(50)
        expect(uuids.count("combo")).to be_within(25).of(50)
      end

      it "should not return expired listings" do
        send_beacon(:heartbeat, hello_server_with_short_ttl)
        sleep 5
        expect(subject.lookup("HelloService")).to be_nil
      end

      it "should not return flatlined servers" do
        send_beacon(:heartbeat, echo_server)
        send_beacon(:heartbeat, combo_server)
        send_beacon(:flatline, echo_server)

        uuids = 100.times.map { subject.lookup("EchoService").uuid }
        expect(uuids.count("combo")).to eq 100
      end

      it "should return up-to-date listings" do
        send_beacon(:heartbeat, echo_server)
        echo_server.port = "7777"
        send_beacon(:heartbeat, echo_server)

        expect(subject.lookup("EchoService").port).to eq "7777"
      end

      context 'when given service identifier is a class name' do
        it 'returns the listing corresponding to the class name' do
          send_beacon(:heartbeat, echo_server)
          expect(subject.lookup(EchoService).uuid).to eq echo_server.uuid
        end
      end
    end

    describe "#restart" do
      it "should clear all listings" do
        send_beacon(:heartbeat, echo_server)
        send_beacon(:heartbeat, combo_server)
        subject.restart
        expect(subject.lookup("EchoService")).to be_nil
      end
    end

    describe "#running" do
      it "should be true" do
        expect(subject).to be_running
      end
    end

    describe "#stop" do
      it "should clear all listings" do
        send_beacon(:heartbeat, echo_server)
        send_beacon(:heartbeat, combo_server)
        subject.stop
        expect(subject.lookup("EchoService")).to be_nil
      end

      it "should stop the server" do
        subject.stop
        expect(subject).to_not be_running
      end
    end
  end

  if ENV.key?("BENCH")
    context "performance" do
      let(:servers) do
        100.times.map do |x|
          ::Protobuf::Rpc::DynamicDiscovery::Server.new(
            :uuid => "performance_server#{x + 1}",
            :address => '127.0.0.1',
            :port => (5555 + x).to_s,
            :ttl => rand(1..5),
            :services => 10.times.map { |y| "PerformanceService#{y}" },
          )
        end
      end

      before do
        require 'benchmark'
        subject.start
        servers.each { |server| send_beacon(:heartbeat, server) }
      end

      after do
        subject.stop
      end

      it "should perform lookups in constant time" do
        print "\n\n"
        Benchmark.bm(17) do |x|
          x.report("  1_000 lookups:") { 1_000.times { subject.lookup("PerformanceService#{rand(0..9)}") } }
          x.report(" 10_000 lookups:") { 10_000.times { subject.lookup("PerformanceService#{rand(0..9)}") } }
          x.report("100_000 lookups:") { 100_000.times { subject.lookup("PerformanceService#{rand(0..9)}") } }
        end
      end
    end
  end
end
