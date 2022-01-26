require 'spec_helper'

RSpec.describe Protobuf::Field::MessageField do
  let(:inner_message) do
    Class.new(::Protobuf::Message) do
      optional :int32, :field, 0
      optional :int32, :field2, 1
    end
  end

  let(:field_message) do
    Class.new(::Protobuf::Message) do
      optional :int32, :field, 1
      repeated :int64, :repeated_field, 2
      optional InnerMessage, :message_field, 3
    end
  end

  let(:message) do
    Class.new(::Protobuf::Message) do
      optional FieldMessage, :message_field, 1
    end
  end

  before do
    stub_const('InnerMessage', inner_message)
    stub_const('FieldMessage', field_message)
    stub_const('Message', message)
  end

  let(:instance) { message.new }

  describe 'setting and getting field' do
    context "when set with the message type" do
      it 'is readable as a message' do
        value = field_message.new(:field => 34)
        instance.message_field = value
        expect(instance.message_field).to eq(value)
      end
    end

    context "when set with #to_proto" do
      let(:to_proto_message) do
        Class.new do
          def to_proto
            FieldMessage.new(:field => 42)
          end
        end
      end

      it 'is readable as a message' do
        value = to_proto_message.new
        instance.message_field = value
        expect(instance.message_field).to eq(value.to_proto)
      end
    end

    context "when set with #to_proto that returns the wrong message type" do
      let(:to_proto_is_wrong_message) do
        Class.new do
          def to_proto
            Message.new
          end
        end
      end

      it 'fails' do
        value = to_proto_is_wrong_message.new
        expect { instance.message_field = value }.to raise_error TypeError
      end
    end

    context "when set with #to_hash" do
      let(:to_hash_message) do
        Class.new do
          def to_hash
            { :field => 989 }
          end
        end
      end

      it 'is readable as a message' do
        value = to_hash_message.new
        instance.message_field = value
        expect(instance.message_field).to eq(field_message.new(value.to_hash))
      end
    end
  end

  describe '#option_set' do
    let(:message_field) { Message.fields[0] }
    it 'returns unless yield' do
      # No Error thrown
      message_field.__send__(:option_set, nil, nil, nil) { false }
      expect do
        message_field.__send__(:option_set, nil, nil, nil) { true }
      end.to raise_error StandardError
    end

    it 'sets repeated fields' do
      repeated = field_message.fields[1]
      instance = field_message.new
      expect(instance.repeated_field!).to eq(nil)
      message_field.__send__(:option_set, instance, repeated, [53]) { true }
      expect(instance.repeated_field!).to eq([53])
      message_field.__send__(:option_set, instance, repeated, [54]) { true }
      expect(instance.repeated_field!).to eq([53, 54])
    end

    it 'sets optional non-message fields' do
      optional = field_message.fields[0]
      instance = field_message.new
      expect(instance.field!).to eq(nil)
      message_field.__send__(:option_set, instance, optional, 53) { true }
      expect(instance.field!).to eq(53)
      message_field.__send__(:option_set, instance, optional, 52) { true }
      expect(instance.field!).to eq(52)
    end

    it 'sets nested inner messages fields one at a time' do
      inner = field_message.fields[2]
      inner_val = InnerMessage.new(:field => 21)
      inner_val2 = InnerMessage.new(:field2 => 9)
      instance = field_message.new
      expect(instance.message_field!).to eq(nil)
      message_field.__send__(:option_set, instance, inner, inner_val) { true }
      expect(instance.message_field!).to eq(InnerMessage.new(:field => 21))
      message_field.__send__(:option_set, instance, inner, inner_val2) { true }
      expect(instance.message_field!).to eq(InnerMessage.new(:field => 21, :field2 => 9))
    end
  end
end
