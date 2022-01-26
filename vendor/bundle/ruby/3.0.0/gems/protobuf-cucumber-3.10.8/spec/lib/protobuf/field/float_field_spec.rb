require 'spec_helper'

RSpec.describe Protobuf::Field::FloatField do

  it_behaves_like :packable_field, described_class do
    let(:value) { [1.0, 2.0, 3.0] }
  end

  class SomeFloatMessage < ::Protobuf::Message
    optional :float, :some_float, 1
  end

  let(:instance) { SomeFloatMessage.new }

  describe 'setting and getting field' do
    subject { instance.some_float = value; instance.some_float }

    context 'when set with an int' do
      let(:value) { 100 }

      it 'is readable as a float' do
        expect(subject).to eq(100.0)
      end
    end

    context 'when set with a float' do
      let(:value) { 100.1 }

      it 'is readable as a float' do
        expect(subject).to eq(100.1)
      end
    end

    context 'when set with a string of a float' do
      let(:value) { "101.1" }

      it 'is readable as a float' do
        expect(subject).to eq(101.1)
      end
    end

    context 'when set with a non-numeric string' do
      let(:value) { "aaaa" }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end

    context 'when set with something that is not a float' do
      let(:value) { [1, 2, 3] }

      it 'throws an error' do
        expect { subject }.to raise_error(TypeError)
      end
    end
  end

  describe '#default_value' do
    context 'optional and required fields' do
      it 'returns the class default' do
        expect(SomeFloatMessage.get_field('some_float').default).to be nil
        expect(::Protobuf::Field::FloatField.default).to eq 0.0
        expect(instance.some_float).to eq 0.0
      end

      context 'with field default' do
        class AnotherFloatMessage < ::Protobuf::Message
          optional :float, :set_float, 1, :default => 3.6
        end

        it 'returns the set default' do
          expect(AnotherFloatMessage.get_field('set_float').default).to eq 3.6
          expect(AnotherFloatMessage.new.set_float).to eq 3.6
        end
      end
    end

    context 'repeated field' do
      class RepeatedFloatMessage < ::Protobuf::Message
        repeated :float, :repeated_float, 1
      end

      it 'returns the set default' do
        expect(RepeatedFloatMessage.new.repeated_float).to eq []
      end
    end
  end

end
