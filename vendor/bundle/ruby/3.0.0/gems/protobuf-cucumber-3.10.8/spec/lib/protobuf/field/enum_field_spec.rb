require 'spec_helper'

RSpec.describe Protobuf::Field::EnumField do
  let(:message) do
    Class.new(::Protobuf::Message) do
      enum_class = Class.new(::Protobuf::Enum) do
        define :POSITIVE, 22
        define :NEGATIVE, -33
      end

      optional enum_class, :enum, 1
    end
  end

  describe '.{encode, decode}' do
    it 'handles positive enum constants' do
      instance = message.new(:enum => :POSITIVE)
      expect(message.decode(instance.encode).enum).to eq(22)
    end

    it 'handles negative enum constants' do
      instance = message.new(:enum => :NEGATIVE)
      expect(message.decode(instance.encode).enum).to eq(-33)
    end
  end

  # https://developers.google.com/protocol-buffers/docs/proto3#json
  describe '.{to_json, from_json}' do
    it 'serialises enum value as string' do
      instance = message.new(:enum => :POSITIVE)
      expect(instance.to_json).to eq('{"enum":"POSITIVE"}')
    end

    it 'deserialises enum value as integer' do
      instance = message.from_json('{"enum":22}')
      expect(instance.enum).to eq(22)
    end

    it 'deserialises enum value as string' do
      instance = message.from_json('{"enum":"NEGATIVE"}')
      expect(instance.enum).to eq(-33)
    end
  end
end
