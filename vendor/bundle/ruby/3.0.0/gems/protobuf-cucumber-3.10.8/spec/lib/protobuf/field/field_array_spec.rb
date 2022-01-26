require 'spec_helper'

RSpec.describe Protobuf::Field::FieldArray do

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

  let(:repeat_message) do
    Class.new(::Protobuf::Message) do
      optional :string, :some_string, 1
      repeated :string, :multiple_strings, 2
      repeated BasicMessage, :multiple_basic_msgs, 3
      repeated SomeEnum, :multiple_enums, 4
    end
  end

  before do
    stub_const('BasicMessage', basic_message)
    stub_const('MoreComplexMessage', more_complex_message)
    stub_const('SomeEnum', some_enum)
    stub_const('SomeRepeatMessage', repeat_message)
  end

  let(:instance) { SomeRepeatMessage.new }

  %w(<< push).each do |method|
    describe "\##{method}" do
      context 'when applied to a string field array' do
        it 'adds a string' do
          expect(instance.multiple_strings).to be_empty
          instance.multiple_strings.send(method, 'string 1')
          expect(instance.multiple_strings).to eq(['string 1'])
          instance.multiple_strings.send(method, 'string 2')
          expect(instance.multiple_strings).to eq(['string 1', 'string 2'])
        end

        it 'fails if not adding a string' do
          expect { instance.multiple_strings.send(method, 100.0) }.to raise_error(TypeError)
        end
      end

      context 'when applied to a MessageField field array' do
        it 'adds a MessageField object' do
          expect(instance.multiple_basic_msgs).to be_empty
          basic_msg1 = BasicMessage.new
          instance.multiple_basic_msgs.send(method, basic_msg1)
          expect(instance.multiple_basic_msgs).to eq([basic_msg1])
          basic_msg2 = BasicMessage.new
          instance.multiple_basic_msgs.send(method, basic_msg2)
          expect(instance.multiple_basic_msgs).to eq([basic_msg1, basic_msg2])
        end

        it 'fails if not adding a MessageField' do
          expect { instance.multiple_basic_msgs.send(method, 100.0) }.to raise_error(TypeError)
        end

        it 'adds a Hash from a MessageField object' do
          expect(instance.multiple_basic_msgs).to be_empty
          basic_msg1 = BasicMessage.new
          basic_msg1.field = 'my value'
          instance.multiple_basic_msgs.send(method, basic_msg1.to_hash)
          expect(instance.multiple_basic_msgs).to eq([basic_msg1])
        end

        it 'does not downcast a MessageField' do
          expect(instance.multiple_basic_msgs).to be_empty
          basic_msg1 = MoreComplexMessage.new
          instance.multiple_basic_msgs.send(method, basic_msg1)
          expect(instance.multiple_basic_msgs).to eq([basic_msg1])
          expect(instance.multiple_basic_msgs.first).to be_a(MoreComplexMessage)
        end
      end

      context 'when applied to an EnumField field array' do
        it 'adds an EnumField object' do
          expect(instance.multiple_enums).to be_empty
          instance.multiple_enums.send(method, SomeEnum::FOO)
          expect(instance.multiple_enums).to eq([SomeEnum::FOO])
          instance.multiple_enums.send(method, SomeEnum::BAR)
          expect(instance.multiple_enums).to eq([SomeEnum::FOO, SomeEnum::BAR])
        end

        it 'fails if not adding an EnumField' do
          expect { instance.multiple_basic_msgs.send(method, 100.0) }.to raise_error(TypeError)
        end
      end
    end
  end
end
