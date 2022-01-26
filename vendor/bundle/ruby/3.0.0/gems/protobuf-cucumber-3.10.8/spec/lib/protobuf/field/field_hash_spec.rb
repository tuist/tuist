require 'spec_helper'

RSpec.describe Protobuf::Field::FieldHash do

  let(:basic_message) do
    Class.new(::Protobuf::Message) do
      optional :string, :field, 1
    end
  end

  let(:more_complex_message) do
    Class.new(BasicMessage) do
    end
  end

  let(:some_enum) do
    Class.new(::Protobuf::Enum) do
      define :FOO, 1
      define :BAR, 2
      define :BAZ, 3
    end
  end

  let(:map_message) do
    Class.new(::Protobuf::Message) do
      optional :string, :some_string, 1
      map :int32, :string, :map_int32_to_string, 2
      map :string, BasicMessage, :map_string_to_msg, 3
      map :string, SomeEnum, :map_string_to_enum, 4
    end
  end

  before do
    stub_const('BasicMessage', basic_message)
    stub_const('MoreComplexMessage', more_complex_message)
    stub_const('SomeEnum', some_enum)
    stub_const('SomeMapMessage', map_message)
  end

  let(:instance) { SomeMapMessage.new }

  %w([]= store).each do |method|
    describe "##{method}" do
      context 'when applied to an int32->string field hash' do
        it 'adds an int -> string entry' do
          expect(instance.map_int32_to_string).to be_empty
          instance.map_int32_to_string.send(method, 1, 'string 1')
          expect(instance.map_int32_to_string).to eq(1 => 'string 1')
          instance.map_int32_to_string.send(method, 2, 'string 2')
          expect(instance.map_int32_to_string).to eq(1 => 'string 1', 2 => 'string 2')
        end

        it 'fails if not adding an int -> string' do
          expect { instance.map_int32_to_string.send(method, 1, 100.0) }.to raise_error(TypeError)
          expect { instance.map_int32_to_string.send(method, 'foo', 100.0) }.to raise_error(TypeError)
          expect { instance.map_int32_to_string.send(method, BasicMessage.new, 100.0) }.to raise_error(TypeError)
          expect { instance.map_int32_to_string.send(method, 'foo', 'bar') }.to raise_error(TypeError)
          expect { instance.map_int32_to_string.send(method, nil, 'foo') }.to raise_error(TypeError)
          expect { instance.map_int32_to_string.send(method, 1, nil) }.to raise_error(TypeError)
        end
      end

      context 'when applied to a string->MessageField field hash' do
        it 'adds a string -> MessageField entry' do
          expect(instance.map_string_to_msg).to be_empty
          basic_msg1 = BasicMessage.new
          instance.map_string_to_msg.send(method, 'msg1', basic_msg1)
          expect(instance.map_string_to_msg).to eq('msg1' => basic_msg1)
          basic_msg2 = BasicMessage.new
          instance.map_string_to_msg.send(method, 'msg2', basic_msg2)
          expect(instance.map_string_to_msg).to eq('msg1' => basic_msg1, 'msg2' => basic_msg2)
        end

        it 'fails if not adding a string -> MessageField entry' do
          expect { instance.map_string_to_msg.send(method, 1, 100.0) }.to raise_error(TypeError)
          expect { instance.map_string_to_msg.send(method, 'foo', SomeEnum::FOO) }.to raise_error(TypeError)
          expect { instance.map_string_to_msg.send(method, SomeEnum::FOO, BasicMessage.new) }.to raise_error(TypeError)
          expect { instance.map_string_to_msg.send(method, nil, BasicMessage.new) }.to raise_error(TypeError)
          expect { instance.map_string_to_msg.send(method, 'foo', nil) }.to raise_error(TypeError)
        end

        it 'adds a Hash from a MessageField object' do
          expect(instance.map_string_to_msg).to be_empty
          basic_msg1 = BasicMessage.new
          basic_msg1.field = 'my value'
          instance.map_string_to_msg.send(method, 'foo', basic_msg1.to_hash)
          expect(instance.map_string_to_msg).to eq('foo' => basic_msg1)
        end

        it 'does not downcast a MessageField' do
          expect(instance.map_string_to_msg).to be_empty
          basic_msg1 = MoreComplexMessage.new
          instance.map_string_to_msg.send(method, 'foo', basic_msg1)
          expect(instance.map_string_to_msg).to eq('foo' => basic_msg1)
          expect(instance.map_string_to_msg['foo']).to be_a(MoreComplexMessage)
        end
      end

      context 'when applied to a string->EnumField field hash' do
        it 'adds a string -> EnumField entry' do
          expect(instance.map_string_to_enum).to be_empty
          instance.map_string_to_enum.send(method, 'msg1', SomeEnum::FOO)
          expect(instance.map_string_to_enum).to eq('msg1' => SomeEnum::FOO)
          instance.map_string_to_enum.send(method, 'msg2', SomeEnum::BAR)
          expect(instance.map_string_to_enum).to eq('msg1' => SomeEnum::FOO, 'msg2' => SomeEnum::BAR)
        end

        it 'fails if not adding a string -> EnumField entry' do
          expect { instance.map_string_to_enum.send(method, 1, 100.0) }.to raise_error(TypeError)
          expect { instance.map_string_to_enum.send(method, nil, 100.0) }.to raise_error(TypeError)
          expect { instance.map_string_to_enum.send(method, 1, nil) }.to raise_error(TypeError)
          expect { instance.map_string_to_enum.send(method, 'foo', BasicMessage.new) }.to raise_error(TypeError)
          expect { instance.map_string_to_enum.send(method, 1, SomeEnum::FOO) }.to raise_error(TypeError)
          expect { instance.map_string_to_enum.send(method, nil, SomeEnum::FOO) }.to raise_error(TypeError)
          expect { instance.map_string_to_enum.send(method, 'foo', nil) }.to raise_error(TypeError)
        end
      end
    end

    describe '#to_hash_value' do
      context 'when applied to an int32->string field hash' do
        before do
          instance.map_int32_to_string[1] = 'string 1'
          instance.map_int32_to_string[2] = 'string 2'
        end

        it 'converts properly' do
          expect(instance.to_hash_value).to eq(:map_int32_to_string => {
            1 => 'string 1',
            2 => 'string 2',
          })
        end
      end

      context 'when applied to a string->MessageField field hash' do
        before do
          instance.map_string_to_msg['msg1'] = BasicMessage.new(:field => 'string 1')
          instance.map_string_to_msg['msg2'] = BasicMessage.new(:field => 'string 2')
        end

        it 'converts properly' do
          expect(instance.to_hash_value).to eq(:map_string_to_msg => {
            'msg1' => {
              :field => 'string 1',
            },
            'msg2' => {
              :field => 'string 2',
            },
          })
        end
      end

      context 'when applied to a string->EnumField field hash' do
        before do
          instance.map_string_to_enum['msg1'] = SomeEnum::FOO
          instance.map_string_to_enum['msg2'] = SomeEnum::BAR
        end

        it 'converts properly' do
          expect(instance.to_hash_value).to eq(:map_string_to_enum => {
            'msg1' => 1,
            'msg2' => 2,
          })
        end
      end
    end
  end
end
