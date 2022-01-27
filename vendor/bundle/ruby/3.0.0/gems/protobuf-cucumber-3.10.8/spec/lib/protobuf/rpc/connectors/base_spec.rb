require 'spec_helper'

RSpec.describe Protobuf::Rpc::Connectors::Base do

  let(:options) do
    { :timeout => 60 }
  end

  subject { Protobuf::Rpc::Connectors::Base.new(options) }

  context "API" do
    specify { expect(subject.respond_to?(:any_callbacks?)).to be true }
    specify { expect(subject.respond_to?(:request_caller)).to be true }
    specify { expect(subject.respond_to?(:data_callback)).to be true }
    specify { expect(subject.respond_to?(:error)).to be true }
    specify { expect(subject.respond_to?(:failure)).to be true }
    specify { expect(subject.respond_to?(:complete)).to be true }
    specify { expect(subject.respond_to?(:parse_response)).to be true }
    specify { expect(subject.respond_to?(:verify_options!)).to be true }
    specify { expect(subject.respond_to?(:verify_callbacks)).to be true }
  end

  describe "#parse_response" do
    let(:options) { { :response_type => Test::Resource, :port => 55589, :host => '127.3.4.5' } }
    it "updates stats#server from the response" do
      allow(subject).to receive(:close_connection)
      subject.instance_variable_set(:@response_data, ::Protobuf::Socketrpc::Response.new(:server => "serverless").encode)
      subject.initialize_stats
      subject.parse_response
      expect(subject.stats.server).to eq("serverless")
    end
    it "does not override stats#server when response.server is missing" do
      allow(subject).to receive(:close_connection)
      subject.instance_variable_set(:@response_data, ::Protobuf::Socketrpc::Response.new.encode)
      subject.initialize_stats
      subject.parse_response
      expect(subject.stats.server).to eq("127.3.4.5:55589")
    end
    it "does not override stats#server when response.server is nil" do
      allow(subject).to receive(:close_connection)
      subject.instance_variable_set(:@response_data, ::Protobuf::Socketrpc::Response.new(:server => nil).encode)
      subject.initialize_stats
      subject.parse_response
      expect(subject.stats.server).to eq("127.3.4.5:55589")
    end
  end

  describe "#any_callbacks?" do
    [:@complete_cb, :@success_cb, :@failure_cb].each do |cb|
      it "returns true if #{cb} is provided" do
        subject.instance_variable_set(cb, "something")
        expect(subject.any_callbacks?).to be true
      end
    end

    it "returns false when all callbacks are not provided" do
      subject.instance_variable_set(:@complete_cb, nil)
      subject.instance_variable_set(:@success_cb, nil)
      subject.instance_variable_set(:@failure_cb, nil)

      expect(subject.any_callbacks?).to be false
    end
  end

  describe "#data_callback" do
    it "changes state to use the data callback" do
      subject.data_callback("data")
      expect(subject.instance_variable_get(:@used_data_callback)).to be true
    end

    it "sets the data var when using the data_callback" do
      subject.data_callback("data")
      expect(subject.instance_variable_get(:@data)).to eq("data")
    end
  end

  describe "#send_request" do
    it "raising an error when 'send_request' is not overridden" do
      expect { subject.send_request }.to raise_error(RuntimeError, /inherit a Connector/)
    end

    it "does not raise error when 'send_request' is overridden" do
      new_sub = Class.new(subject.class) { def send_request; end }.new(options)
      expect { new_sub.send_request }.to_not raise_error
    end
  end

  describe '.new' do
    it 'assigns passed options and initializes success/failure callbacks' do
      expect(subject.options).to eq(Protobuf::Rpc::Connectors::DEFAULT_OPTIONS.merge(options))
      expect(subject.success_cb).to be_nil
      expect(subject.failure_cb).to be_nil
    end
  end

  describe '#success_cb' do
    it 'allows setting the success callback and calling it' do
      expect(subject.success_cb).to be_nil
      cb = proc { |res| fail res }
      subject.success_cb = cb
      expect(subject.success_cb).to eq(cb)
      expect { subject.success_cb.call('an error from cb') }.to raise_error 'an error from cb'
    end
  end

  describe '#failure_cb' do
    it 'allows setting the failure callback and calling it' do
      expect(subject.failure_cb).to be_nil
      cb = proc { |res| fail res }
      subject.failure_cb = cb
      expect(subject.failure_cb).to eq(cb)
      expect { subject.failure_cb.call('an error from cb') }.to raise_error 'an error from cb'
    end
  end

  describe '#request_bytes' do
    let(:service) { Test::ResourceService }
    let(:method) { :find }
    let(:request) { '' }
    let(:client_host) { 'myhost.myservice.com' }
    let(:options) do
      {
        :service => service,
        :method => method,
        :request => request,
        :client_host => client_host,
        :timeout => 60,
      }
    end

    let(:expected) do
      ::Protobuf::Socketrpc::Request.new(
        :service_name => service.name,
        :method_name => 'find',
        :request_proto => '',
        :caller => client_host,
      )
    end

    before { allow(subject).to receive(:validate_request_type!).and_return(true) }
    before { expect(subject).not_to receive(:failure) }

    specify { expect(subject.request_bytes).to eq expected.encode }
  end

  describe '#request_caller' do
    specify { expect(subject.request_caller).to eq ::Protobuf.client_host }

    context 'when "client_host" option is given to initializer' do
      let(:hostname) { 'myhost.myserver.com' }
      let(:options) { { :client_host => hostname, :timeout => 60 } }

      specify { expect(subject.request_caller).to_not eq ::Protobuf.client_host }
      specify { expect(subject.request_caller).to eq hostname }
    end
  end

  describe "#verify_callbacks" do
    it "sets @failure_cb to #data_callback when no callbacks are defined" do
      subject.verify_callbacks
      expect(subject.instance_variable_get(:@failure_cb)).to eq(subject.method(:data_callback))
    end

    it "sets @success_cb to #data_callback when no callbacks are defined" do
      subject.verify_callbacks
      expect(subject.instance_variable_get(:@success_cb)).to eq(subject.method(:data_callback))
    end

    it "doesn't set @failure_cb when already defined" do
      set_cb = -> { true }
      subject.instance_variable_set(:@failure_cb, set_cb)
      subject.verify_callbacks
      expect(subject.instance_variable_get(:@failure_cb)).to eq(set_cb)
      expect(subject.instance_variable_get(:@failure_cb)).to_not eq(subject.method(:data_callback))
    end

    it "doesn't set @success_cb when already defined" do
      set_cb = -> { true }
      subject.instance_variable_set(:@success_cb, set_cb)
      subject.verify_callbacks
      expect(subject.instance_variable_get(:@success_cb)).to eq(set_cb)
      expect(subject.instance_variable_get(:@success_cb)).to_not eq(subject.method(:data_callback))
    end

  end

  shared_examples "a ConnectorDisposition" do |meth, cb, *args|

    it "calls #complete before exit" do
      subject.stats = ::Protobuf::Rpc::Stat.new(:stop => true)

      expect(subject).to receive(:complete)
      subject.method(meth).call(*args)
    end

    it "calls the #{cb} callback when provided" do
      stats = ::Protobuf::Rpc::Stat.new
      allow(stats).to receive(:stop).and_return(true)
      subject.stats = stats
      some_cb = double("Object")

      subject.instance_variable_set("@#{cb}", some_cb)
      expect(some_cb).to receive(:call).and_return(true)
      subject.method(meth).call(*args)
    end

    it "calls the complete callback when provided" do
      stats = ::Protobuf::Rpc::Stat.new
      allow(stats).to receive(:stop).and_return(true)
      subject.stats = stats
      comp_cb = double("Object")

      subject.instance_variable_set(:@complete_cb, comp_cb)
      expect(comp_cb).to receive(:call).and_return(true)
      subject.method(meth).call(*args)
    end

  end

  it_behaves_like("a ConnectorDisposition", :failure, "failure_cb", :RPC_ERROR, "message")
  it_behaves_like("a ConnectorDisposition", :failure, "complete_cb", :RPC_ERROR, "message")
  it_behaves_like("a ConnectorDisposition", :succeed, "complete_cb", "response")
  it_behaves_like("a ConnectorDisposition", :succeed, "success_cb", "response")
  it_behaves_like("a ConnectorDisposition", :complete, "complete_cb")

end
