require 'spec_helper'
require 'protobuf/field'
require PROTOS_PATH.join('resource.pb')

RSpec.describe ::Protobuf::Field do

  describe '.build' do
    pending
  end

  describe '.field_class' do
    context 'when type is an enum class' do
      it 'returns an enum field' do
        expect(subject.field_class(::Test::EnumTestType)).to eq(::Protobuf::Field::EnumField)
        expect(subject.field_type(::Test::EnumTestType)).to eq(::Test::EnumTestType)
      end
    end

    context 'when type is a message class' do
      it 'returns a message field' do
        expect(subject.field_class(::Test::Resource)).to eq(::Protobuf::Field::MessageField)
        expect(subject.field_type(::Test::Resource)).to eq(::Test::Resource)
      end
    end

    context 'when type is a base field class' do
      it 'returns that class' do
        expect(subject.field_class(::Protobuf::Field::BoolField)).to eq(::Protobuf::Field::BoolField)
      end
    end

    context 'when type is a double field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::DoubleField
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:double)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:double)).to eq(expected_field)
      end
    end

    context 'when type is a float field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::FloatField
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:float)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:float)).to eq(expected_field)
      end
    end

    context 'when type is a int32 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Int32Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:int32)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:int32)).to eq(expected_field)
      end
    end

    context 'when type is a int64 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Int64Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:int64)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:int64)).to eq(expected_field)
      end
    end

    context 'when type is a uint32 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Uint32Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:uint32)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:uint32)).to eq(expected_field)
      end
    end

    context 'when type is a uint64 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Uint64Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:uint64)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:uint64)).to eq(expected_field)
      end
    end

    context 'when type is a sint32 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Sint32Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:sint32)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:sint32)).to eq(expected_field)
      end
    end

    context 'when type is a sint64 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Sint64Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:sint64)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:sint64)).to eq(expected_field)
      end
    end

    context 'when type is a fixed32 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Fixed32Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:fixed32)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:fixed32)).to eq(expected_field)
      end
    end

    context 'when type is a fixed64 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Fixed64Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:fixed64)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:fixed64)).to eq(expected_field)
      end
    end

    context 'when type is a sfixed32 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Sfixed32Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:sfixed32)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:sfixed32)).to eq(expected_field)
      end
    end

    context 'when type is a sfixed64 field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::Sfixed64Field
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:sfixed64)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:sfixed64)).to eq(expected_field)
      end
    end

    context 'when type is a string field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::StringField
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:string)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:string)).to eq(expected_field)
      end
    end

    context 'when type is a bytes field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::BytesField
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:bytes)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:bytes)).to eq(expected_field)
      end
    end

    context 'when type is a bool field class or symbol' do
      it 'returns that class' do
        expected_field = ::Protobuf::Field::BoolField
        expect(subject.field_class(expected_field)).to eq(expected_field)
        expect(subject.field_class(:bool)).to eq(expected_field)
        expect(subject.field_type(expected_field)).to eq(expected_field)
        expect(subject.field_type(:bool)).to eq(expected_field)
      end
    end

    context 'when type is not mapped' do
      it 'raises an ArgumentError' do
        expect do
          subject.field_class("boom")
        end.to raise_error(ArgumentError)
      end
    end

  end

end
