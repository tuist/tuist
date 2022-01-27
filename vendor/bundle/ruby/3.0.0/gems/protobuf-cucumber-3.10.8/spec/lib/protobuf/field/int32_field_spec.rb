require 'spec_helper'

RSpec.describe Protobuf::Field::Int32Field do

  it_behaves_like :packable_field, described_class

  class SomeInt32Message < ::Protobuf::Message
    optional :int32, :some_int, 1
  end

  let(:instance) { SomeInt32Message.new }

  describe 'setting and getting a field' do
    subject { instance.some_int = value; instance.some_int }

    context 'when set with an int' do
      let(:value) { 100 }

      it 'is readable as an int' do
        expect(subject).to eq(100)
      end
    end

    context 'when set with a float' do
      let(:value) { 100.1 }

      it 'is readable as an int' do
        expect(subject).to eq(100)
      end
    end

    context 'when set with a string of an int' do
      let(:value) { "101" }

      it 'is readable as an int' do
        expect(subject).to eq(101)
      end
    end

    context 'when set with a negative representation of an int as string' do
      let(:value) { "-101" }

      it 'is readable as a negative int' do
        expect(subject).to eq(-101)
      end
    end

    context 'when set with a non-numeric string' do
      let(:value) { "aaaa" }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end

    context 'when set with a string of an int in hex format' do
      let(:value) { "0x101" }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end

    context 'when set with a string of an int larger than int32 max' do
      let(:value) { (described_class.max + 1).to_s }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end

    context 'when set with something that is not an int' do
      let(:value) { [1, 2, 3] }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end

    context 'when set with a timestamp' do
      let(:value) { Time.now }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end
  end

  describe '#default_value' do
    context 'optional and required fields' do
      it 'returns the class default' do
        expect(SomeInt32Message.get_field('some_int').default).to be nil
        expect(::Protobuf::Field::Int32Field.default).to eq 0
        expect(instance.some_int).to eq 0
      end

      context 'with field default' do
        class AnotherIntMessage < ::Protobuf::Message
          optional :int32, :set_int, 1, :default => 3
        end

        it 'returns the set default' do
          expect(AnotherIntMessage.get_field('set_int').default).to eq 3
          expect(AnotherIntMessage.new.set_int).to eq 3
        end
      end
    end

    context 'repeated field' do
      class RepeatedIntMessage < ::Protobuf::Message
        repeated :int32, :repeated_int, 1
      end

      it 'returns the set default' do
        expect(RepeatedIntMessage.new.repeated_int).to eq []
      end
    end
  end

end
