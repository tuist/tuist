require 'spec_helper'
require 'protobuf'

RSpec.describe ::Protobuf do

  describe '.client_host' do
    after { ::Protobuf.client_host = nil }

    subject { ::Protobuf.client_host }

    context 'when client_host is not pre-configured' do
      it { is_expected.to eq ::Socket.gethostname }
    end

    context 'when client_host is pre-configured' do
      let(:hostname) { 'override.myhost.com' }
      before { ::Protobuf.client_host = hostname }
      it { is_expected.to eq hostname }
    end
  end

  describe '.connector_type_class' do
    it "defaults to Socket" do
      described_class.connector_type_class = nil
      expect(described_class.connector_type_class).to eq(::Protobuf::Rpc::Connectors::Socket)
    end

    it 'fails if fails to load the PB_CLIENT_TYPE' do
      ENV['PB_CLIENT_TYPE'] = "something_to_autoload"
      expect { load 'protobuf.rb' }.to raise_error(LoadError, /something_to_autoload/)
      ENV.delete('PB_CLIENT_TYPE')
    end

    it 'loads the connector type class from PB_CLIENT_TYPE' do
      ENV['PB_CLIENT_TYPE'] = "protobuf/rpc/connectors/zmq"
      load 'protobuf.rb'
      expect(::Protobuf.connector_type_class).to eq(::Protobuf::Rpc::Connectors::Zmq)
      ENV.delete('PB_CLIENT_TYPE')
    end
  end

  describe '.gc_pause_server_request?' do
    before { described_class.instance_variable_set(:@gc_pause_server_request, nil) }

    it 'defaults to a false value' do
      expect(described_class.gc_pause_server_request?).to be false
    end

    it 'is settable' do
      described_class.gc_pause_server_request = true
      expect(described_class.gc_pause_server_request?).to be true
    end
  end

  describe '.print_deprecation_warnings?' do
    around do |example|
      orig = described_class.print_deprecation_warnings?
      example.call
      described_class.print_deprecation_warnings = orig
    end

    it 'defaults to a true value' do
      allow(ENV).to receive(:key?).with('PB_IGNORE_DEPRECATIONS').and_return(false)
      described_class.instance_variable_set('@field_deprecator', nil)
      expect(described_class.print_deprecation_warnings?).to be true
    end

    it 'is settable' do
      described_class.print_deprecation_warnings = false
      expect(described_class.print_deprecation_warnings?).to be false
    end

    context 'when ENV["PB_IGNORE_DEPRECATIONS"] present' do
      it 'defaults to a false value' do
        allow(ENV).to receive(:key?).with('PB_IGNORE_DEPRECATIONS').and_return(true)
        described_class.instance_variable_set('@field_deprecator', nil)
        expect(described_class.print_deprecation_warnings?).to be false
      end
    end
  end

  describe '.ignore_unknown_fields?' do
    around do |example|
      orig = described_class.ignore_unknown_fields?
      example.call
      described_class.ignore_unknown_fields = orig
    end

    it 'defaults to a true value' do
      if described_class.instance_variable_defined?('@ignore_unknown_fields')
        described_class.send(:remove_instance_variable, '@ignore_unknown_fields')
      end
      expect(described_class.ignore_unknown_fields?).to be true
    end

    it 'is settable' do
      expect do
        described_class.ignore_unknown_fields = false
      end.to change {
        described_class.ignore_unknown_fields?
      }.from(true).to(false)
    end
  end

end
