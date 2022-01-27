require 'spec_helper'

require 'protobuf/generators/field_generator'

RSpec.describe ::Protobuf::Generators::FieldGenerator do

  let(:label_enum) { :LABEL_OPTIONAL }
  let(:name) { 'foo_bar' }
  let(:number) { 3 }
  let(:type_enum) { :TYPE_STRING }
  let(:type_name) { nil }
  let(:default_value) { nil }
  let(:extendee) { nil }
  let(:field_options) { {} }

  let(:field_fields) do
    {
      :label => label_enum,
      :name => name,
      :number => number,
      :type => type_enum,
      :type_name => type_name,
      :default_value => default_value,
      :extendee => extendee,
      :options => field_options,
    }
  end
  let(:field) { ::Google::Protobuf::FieldDescriptorProto.new(field_fields) }

  let(:nested_types) { [] }
  let(:owner_fields) do
    {
      :name => 'Baz',
      :field => [field],
      :nested_type => nested_types,
    }
  end
  let(:owner_msg) { ::Google::Protobuf::DescriptorProto.new(owner_fields) }

  describe '#compile' do
    subject { described_class.new(field, owner_msg, 1).to_s }

    specify { expect(subject).to eq "  optional :string, :foo_bar, 3\n" }

    context 'when the type is another message' do
      let(:type_enum) { :TYPE_MESSAGE }
      let(:type_name) { '.foo.bar.Baz' }

      specify { expect(subject).to eq "  optional ::Foo::Bar::Baz, :foo_bar, 3\n" }
    end

    context 'when a default value is used' do
      let(:type_enum) { :TYPE_INT32 }
      let(:default_value) { '42' }
      specify { expect(subject).to eq "  optional :int32, :foo_bar, 3, :default => 42\n" }

      context 'when type is an enum' do
        let(:type_enum) { :TYPE_ENUM }
        let(:type_name) { '.foo.bar.Baz' }
        let(:default_value) { 'QUUX' }

        specify { expect(subject).to eq "  optional ::Foo::Bar::Baz, :foo_bar, 3, :default => ::Foo::Bar::Baz::QUUX\n" }
      end

      context 'when type is an enum with lowercase default value with PB_UPCASE_ENUMS set' do
        let(:type_enum) { :TYPE_ENUM }
        let(:type_name) { '.foo.bar.Baz' }
        let(:default_value) { 'quux' }
        before { allow(ENV).to receive(:key?).with('PB_UPCASE_ENUMS').and_return(true) }

        specify { expect(subject).to eq "  optional ::Foo::Bar::Baz, :foo_bar, 3, :default => ::Foo::Bar::Baz::QUUX\n" }
      end

      context 'when the type is a string' do
        let(:type_enum) { :TYPE_STRING }
        let(:default_value) { "a default \"string\"" }

        specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :default => \"a default \"string\"\"\n" }
      end

      context 'when float or double field type' do
        let(:type_enum) { :TYPE_DOUBLE }

        context 'when the default value is "nan"' do
          let(:default_value) { 'nan' }
          specify { expect(subject).to match(/::Float::NAN/) }
        end

        context 'when the default value is "inf"' do
          let(:default_value) { 'inf' }
          specify { expect(subject).to match(/::Float::INFINITY/) }
        end

        context 'when the default value is "-inf"' do
          let(:default_value) { '-inf' }
          specify { expect(subject).to match(/-::Float::INFINITY/) }
        end
      end
    end

    context 'when the field is an extension' do
      let(:extendee) { 'foo.bar.Baz' }

      specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :extension => true\n" }
    end

    context 'when field is packed' do
      let(:field_options) { { :packed => true } }

      specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :packed => true\n" }
    end

    context 'when field is a map' do
      let(:type_enum) { :TYPE_MESSAGE }
      let(:type_name) { '.foo.bar.Baz.FooBarEntry' }
      let(:label_enum) { :LABEL_REPEATED }
      let(:nested_types) do
        [::Google::Protobuf::DescriptorProto.new(
          :name => 'FooBarEntry',
          :field => [
            ::Google::Protobuf::FieldDescriptorProto.new(
              :label => :LABEL_OPTIONAL,
              :name => 'key',
              :number => 1,
              :type => :TYPE_STRING,
              :type_name => nil),
            ::Google::Protobuf::FieldDescriptorProto.new(
              :label => :LABEL_OPTIONAL,
              :name => 'value',
              :number => 2,
              :type => :TYPE_ENUM,
              :type_name => '.foo.bar.SnafuState'),
          ],
          :options => ::Google::Protobuf::MessageOptions.new(:map_entry => true)),
        ]
      end

      specify { expect(subject).to eq "  map :string, ::Foo::Bar::SnafuState, :foo_bar, 3\n" }
    end

    context 'when field is deprecated' do
      let(:field_options) { { :deprecated => true } }

      specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :deprecated => true\n" }
    end

    context 'when field uses a custom option that is an extension' do
      class ::CustomFieldEnum < ::Protobuf::Enum
        define :BOOM, 1
        define :BAM, 2
      end

      class ::CustomFieldMessage < ::Protobuf::Message
        optional :string, :foo, 1
      end

      class ::Google::Protobuf::FieldOptions < ::Protobuf::Message
        optional :string, :custom_string_option, 22000, :extension => true
        optional :bool, :custom_bool_option, 22001, :extension => true
        optional :int32, :custom_int32_option, 22002, :extension => true
        optional ::CustomFieldEnum, :custom_enum_option, 22003, :extension => true
        optional ::CustomFieldMessage, :custom_message_option, 22004, :extension => true
      end

      describe 'option has a string value' do
        let(:field_options) { { :custom_string_option => 'boom' } }

        specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :custom_string_option => \"boom\"\n" }
      end

      describe 'option has a bool value' do
        let(:field_options) { { :custom_bool_option => true } }

        specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :custom_bool_option => true\n" }
      end

      describe 'option has a int32 value' do
        let(:field_options) { { :custom_int32_option => 123 } }

        specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :custom_int32_option => 123\n" }
      end

      describe 'option has a message value' do
        let(:field_options) { { :custom_message_option => CustomFieldMessage.new(:foo => 'boom') } }

        specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :custom_message_option => { :foo => \"boom\" }\n" }
      end

      describe 'option has a enum value' do
        let(:field_options) { { :custom_enum_option => CustomFieldEnum::BAM } }

        specify { expect(subject).to eq "  optional :string, :foo_bar, 3, :custom_enum_option => ::CustomFieldEnum::BAM\n" }
      end
    end
  end

end
