require 'spec_helper'

RSpec.describe Protobuf::Field::Fixed64Field do

  it_behaves_like :packable_field, described_class

  let(:message) do
    Class.new(::Protobuf::Message) do
      optional :fixed64, :some_field, 1
    end
  end

  # https://developers.google.com/protocol-buffers/docs/proto3#json
  describe '.{to_json, from_json}' do
    it 'serialises 0' do
      instance = message.new(some_field: 0)
      expect(instance.to_json(proto3: true)).to eq('{}')
      expect(instance.to_json).to eq('{"some_field":0}')
    end

    it 'serialises max value' do
      instance = message.new(some_field: described_class.max)
      expect(instance.to_json(proto3: true)).to eq('{"someField":"18446744073709551615"}')
      expect(instance.to_json).to eq('{"some_field":18446744073709551615}')
    end

    it 'serialises min value' do
      instance = message.new(some_field: described_class.min)
      expect(instance.to_json(proto3: true)).to eq('{}')
      expect(instance.to_json).to eq('{"some_field":0}')
    end
  end
end
