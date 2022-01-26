# encoding: utf-8

require 'spec_helper'

RSpec.describe ::Protobuf::Field::StringField do

  describe '#encode' do
    context 'when a repeated string field contains frozen strings' do
      it 'does not raise an encoding error' do
        expect do
          frozen_strings = ["foo".freeze, "bar".freeze, "baz".freeze]
          ::Test::ResourceFindRequest.encode(:name => 'resource', :widgets => frozen_strings)
        end.not_to raise_error
      end
    end

    context 'when a repeated bytes field contains frozen strings' do
      it 'does not raise an encoding error' do
        expect do
          frozen_strings = ["foo".freeze, "bar".freeze, "baz".freeze]
          ::Test::ResourceFindRequest.encode(:name => 'resource', :widget_bytes => frozen_strings)
        end.not_to raise_error
      end
    end

    it 'does not alter string values after encoding multiple times' do
      source_string = "foo"
      proto = ::Test::Resource.new(:name => source_string)
      proto.encode
      expect(proto.name).to eq source_string
      proto.encode
      expect(proto.name).to eq source_string
    end

    it 'does not alter unicode string values after encoding multiple times' do
      source_string = "¢"
      proto = ::Test::Resource.new(:name => source_string)
      proto.encode
      expect(proto.name).to eq source_string
      proto.encode
      expect(proto.name).to eq source_string
    end
  end

  describe '#default_value' do
    context 'optional and required fields' do
      it 'returns the class default' do
        class SomeStringMessage < ::Protobuf::Message
          optional :string, :some_string, 1
        end
        expect(SomeStringMessage.get_field('some_string').default).to be nil
        expect(::Protobuf::Field::StringField.default).to eq ""
        expect(SomeStringMessage.new.some_string).to eq ""
      end

      context 'with field default' do
        class AnotherStringMessage < ::Protobuf::Message
          optional :string, :set_string, 1, :default => "default value this is"
        end

        it 'returns the set default' do
          expect(AnotherStringMessage.get_field('set_string').default).to eq "default value this is"
          expect(AnotherStringMessage.new.set_string).to eq "default value this is"
        end
      end
    end

    context 'repeated field' do
      class RepeatedStringMessage < ::Protobuf::Message
        repeated :string, :repeated_string, 1
      end

      it 'returns the set default' do
        expect(RepeatedStringMessage.new.repeated_string).to eq []
      end
    end
  end

end
