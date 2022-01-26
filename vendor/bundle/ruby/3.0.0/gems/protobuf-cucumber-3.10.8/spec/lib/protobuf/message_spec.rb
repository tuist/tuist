# encoding: utf-8

require 'stringio'
require 'spec_helper'
require PROTOS_PATH.join('resource.pb')
require PROTOS_PATH.join('enum.pb')

RSpec.describe Protobuf::Message do

  describe '.decode' do
    let(:message) { ::Test::Resource.new(:name => "Jim") }

    it 'creates a new message object decoded from the given bytes' do
      expect(::Test::Resource.decode(message.encode)).to eq message
    end

    context 'with a new enum value' do
      let(:older_message) do
        Class.new(Protobuf::Message) do
          enum_class = Class.new(::Protobuf::Enum) do
            define :YAY, 1
          end

          optional enum_class, :enum_field, 1
          repeated enum_class, :enum_list, 2
        end
      end

      let(:newer_message) do
        Class.new(Protobuf::Message) do
          enum_class = Class.new(::Protobuf::Enum) do
            define :YAY, 1
            define :HOORAY, 2
          end

          optional enum_class, :enum_field, 1
          repeated enum_class, :enum_list, 2
        end
      end

      context 'with a singular field' do
        it 'treats the field as if it was unset when decoding' do
          newer = newer_message.new(:enum_field => :HOORAY).serialize

          expect(older_message.decode(newer).enum_field!).to be_nil
        end

        it 'rejects an unknown value when using the constructor' do
          expect { older_message.new(:enum_field => :HOORAY) }.to raise_error(TypeError)
        end

        it 'rejects an unknown value when the setter' do
          older = older_message.new
          expect { older.enum_field = :HOORAY }.to raise_error(TypeError)
        end
      end

      context 'with a repeated field' do
        it 'treats the field as if it was unset when decoding' do
          newer = newer_message.new(:enum_list => [:HOORAY]).serialize

          expect(older_message.decode(newer).enum_list).to eq([])
        end

        it 'rejects an unknown value when using the constructor' do
          expect { older_message.new(:enum_list => [:HOORAY]) }.to raise_error(TypeError)
        end

        it 'rejects an unknown value when the setter' do
          older = older_message.new
          expect { older.enum_field = [:HOORAY] }.to raise_error(TypeError)
        end
      end
    end
  end

  describe '.decode_from' do
    let(:message) { ::Test::Resource.new(:name => "Jim") }

    it 'creates a new message object decoded from the given byte stream' do
      stream = ::StringIO.new(message.encode)
      expect(::Test::Resource.decode_from(stream)).to eq message
    end
  end

  describe 'defining a new field' do
    context 'when defining a field with a tag that has already been used' do
      it 'raises a TagCollisionError' do
        expect do
          Class.new(Protobuf::Message) do
            optional ::Protobuf::Field::Int32Field, :foo, 1
            optional ::Protobuf::Field::Int32Field, :bar, 1
          end
        end.to raise_error(Protobuf::TagCollisionError, /Field number 1 has already been used/)
      end
    end

    context 'when defining an extension field with a tag that has already been used' do
      it 'raises a TagCollisionError' do
        expect do
          Class.new(Protobuf::Message) do
            extensions 100...110
            optional ::Protobuf::Field::Int32Field, :foo, 100
            optional ::Protobuf::Field::Int32Field, :bar, 100, :extension => true
          end
        end.to raise_error(Protobuf::TagCollisionError, /Field number 100 has already been used/)
      end
    end

    context 'when defining a field with a name that has already been used' do
      it 'raises a DuplicateFieldNameError' do
        expect do
          Class.new(Protobuf::Message) do
            optional ::Protobuf::Field::Int32Field, :foo, 1
            optional ::Protobuf::Field::Int32Field, :foo, 2
          end
        end.to raise_error(Protobuf::DuplicateFieldNameError, /Field name foo has already been used/)
      end
    end

    context 'when defining an extension field with a name that has already been used' do
      it 'raises a DuplicateFieldNameError' do
        expect do
          Class.new(Protobuf::Message) do
            extensions 100...110
            optional ::Protobuf::Field::Int32Field, :foo, 1
            optional ::Protobuf::Field::Int32Field, :foo, 100, :extension => true
          end
        end.to raise_error(Protobuf::DuplicateFieldNameError, /Field name foo has already been used/)
      end
    end
  end

  describe '.encode' do
    let(:values) { { :name => "Jim" } }

    it 'creates a new message object with the given values and returns the encoded bytes' do
      expect(::Test::Resource.encode(values)).to eq ::Test::Resource.new(values).encode
    end
  end

  describe '#initialize' do
    it "defaults to the first value listed in the enum's type definition" do
      test_enum = Test::EnumTestMessage.new
      expect(test_enum.non_default_enum).to eq(Test::EnumTestType.enums.first)
    end

    it "defaults to a a value with a name" do
      test_enum = Test::EnumTestMessage.new
      expect(test_enum.non_default_enum.name).to eq(Test::EnumTestType.enums.first.name)
    end

    it "exposes the enum getter raw value through ! method" do
      test_enum = Test::EnumTestMessage.new
      expect(test_enum.non_default_enum!).to be_nil
    end

    it "exposes the enum getter raw value through ! method (when set)" do
      test_enum = Test::EnumTestMessage.new
      test_enum.non_default_enum = 1
      expect(test_enum.non_default_enum!).to eq(1)
    end

    it "does not try to set attributes which have nil values" do
      expect_any_instance_of(Test::EnumTestMessage).not_to receive("non_default_enum=")
      Test::EnumTestMessage.new(:non_default_enum => nil)
    end

    it "takes a hash as an initialization argument" do
      test_enum = Test::EnumTestMessage.new(:non_default_enum => 2)
      expect(test_enum.non_default_enum).to eq(2)
    end

    it "initializes with an object that responds to #to_hash" do
      hashie_object = OpenStruct.new(:to_hash => { :non_default_enum => 2 })
      test_enum = Test::EnumTestMessage.new(hashie_object)
      expect(test_enum.non_default_enum).to eq(2)
    end

    it "initializes with an object with a block" do
      test_enum = Test::EnumTestMessage.new { |p| p.non_default_enum = 2 }
      expect(test_enum.non_default_enum).to eq(2)
    end

    # to be deprecated
    it "allows you to pass nil to repeated fields" do
      test = Test::Resource.new(:repeated_enum => nil)
      expect(test.repeated_enum).to eq([])
    end
  end

  describe '#encode' do
    context "encoding" do
      it "accepts UTF-8 strings into string fields" do
        message = ::Test::Resource.new(:name => "Kyle Redfearn\u0060s iPad")

        expect { message.encode }.to_not raise_error
      end

      it "keeps utf-8 when utf-8 is input for string fields" do
        name = 'my name💩'
        name.force_encoding(Encoding::UTF_8)

        message = ::Test::Resource.new(:name => name)
        new_message = ::Test::Resource.decode(message.encode)
        expect(new_message.name == name).to be true
      end

      it "trims binary when binary is input for string fields" do
        name = "my name\xC3"
        name.force_encoding(Encoding::BINARY)

        message = ::Test::Resource.new(:name => name)
        new_message = ::Test::Resource.decode(message.encode)
        expect(new_message.name == "my name").to be true
      end
    end

    context "when there's no value for a required field" do
      let(:message) { ::Test::ResourceWithRequiredField.new }

      it "raises a 'message not initialized' error" do
        expect do
          message.encode
        end.to raise_error(Protobuf::SerializationError, /required/i)
      end
    end

    context "repeated fields" do
      let(:message) { ::Test::Resource.new(:name => "something") }

      it "does not raise an error when repeated fields are []" do
        expect do
          message.repeated_enum = []
          message.encode
        end.to_not raise_error
      end

      it "sets the value to nil when empty array is passed" do
        message.repeated_enum = []
        expect(message.instance_variable_get("@values")[:repeated_enum]).to be_nil
      end

      it "does not compact the edit original array" do
        a = [nil].freeze
        message.repeated_enum = a
        expect(message.repeated_enum).to eq([])
        expect(a).to eq([nil].freeze)
      end

      it "compacts the set array" do
        message.repeated_enum = [nil]
        expect(message.repeated_enum).to eq([])
      end

      it "raises TypeError when a non-array replaces it" do
        expect do
          message.repeated_enum = 2
        end.to raise_error(/value of type/)
      end
    end
  end

  describe "boolean predicate methods" do
    subject { Test::ResourceFindRequest.new(:name => "resource") }

    it { is_expected.to respond_to(:active?) }

    it "sets the predicate to true when the boolean value is true" do
      subject.active = true
      expect(subject.active?).to be true
    end

    it "sets the predicate to false when the boolean value is false" do
      subject.active = false
      expect(subject.active?).to be false
    end

    it "does not put predicate methods on non-boolean fields" do
      expect(Test::ResourceFindRequest.new(:name => "resource")).to_not respond_to(:name?)
    end
  end

  describe "#respond_to_and_has?" do
    subject { Test::EnumTestMessage.new(:non_default_enum => 2) }

    it "is false when the message does not have the field" do
      expect(subject.respond_to_and_has?(:other_field)).to be false
    end

    it "is true when the message has the field" do
      expect(subject.respond_to_and_has?(:non_default_enum)).to be true
    end
  end

  describe "#respond_to_has_and_present?" do
    subject { Test::EnumTestMessage.new(:non_default_enum => 2) }

    it "is false when the message does not have the field" do
      expect(subject.respond_to_and_has_and_present?(:other_field)).to be false
    end

    it "is false when the field is repeated and a value is not present" do
      expect(subject.respond_to_and_has_and_present?(:repeated_enums)).to be false
    end

    it "is false when the field is repeated and the value is empty array" do
      subject.repeated_enums = []
      expect(subject.respond_to_and_has_and_present?(:repeated_enums)).to be false
    end

    it "is true when the field is repeated and a value is present" do
      subject.repeated_enums = [2]
      expect(subject.respond_to_and_has_and_present?(:repeated_enums)).to be true
    end

    it "is true when the message has the field" do
      expect(subject.respond_to_and_has_and_present?(:non_default_enum)).to be true
    end

    context "#API" do
      subject { Test::EnumTestMessage.new(:non_default_enum => 2) }

      specify { expect(subject).to respond_to(:respond_to_and_has_and_present?) }
      specify { expect(subject).to respond_to(:responds_to_and_has_and_present?) }
      specify { expect(subject).to respond_to(:responds_to_has?) }
      specify { expect(subject).to respond_to(:respond_to_has?) }
      specify { expect(subject).to respond_to(:respond_to_has_present?) }
      specify { expect(subject).to respond_to(:responds_to_has_present?) }
      specify { expect(subject).to respond_to(:respond_to_and_has_present?) }
      specify { expect(subject).to respond_to(:responds_to_and_has_present?) }
    end

  end

  describe '#inspect' do
    let(:klass) do
      Class.new(Protobuf::Message) do |klass|
        enum_class = Class.new(Protobuf::Enum) do
          define :YAY, 1
        end

        klass.const_set(:EnumKlass, enum_class)

        optional :string, :name, 1
        repeated :int32, :counts, 2
        optional enum_class, :enum, 3
      end
    end

    before { stub_const('MyMessage', klass) }

    it 'lists the fields' do
      proto = klass.new(:name => 'wooo', :counts => [1, 2, 3], :enum => klass::EnumKlass::YAY)
      expect(proto.inspect).to eq('#<MyMessage name="wooo" counts=[1, 2, 3] enum=#<Protobuf::Enum(MyMessage::EnumKlass)::YAY=1>>')
    end
  end

  describe '#to_hash' do
    context 'generating values for an ENUM field' do
      it 'converts the enum to its tag representation' do
        hash = Test::EnumTestMessage.new(:non_default_enum => :TWO).to_hash
        expect(hash).to eq(:non_default_enum => 2)
      end

      it 'does not populate default values' do
        hash = Test::EnumTestMessage.new.to_hash
        expect(hash).to eq({})
      end

      it 'converts repeated enum fields to an array of the tags' do
        hash = Test::EnumTestMessage.new(:repeated_enums => [:ONE, :TWO, :TWO, :ONE]).to_hash
        expect(hash).to eq(:repeated_enums => [1, 2, 2, 1])
      end
    end

    context 'generating values for a Message field' do
      it 'recursively hashes field messages' do
        hash = Test::Nested.new(:resource => { :name => 'Nested' }).to_hash
        expect(hash).to eq(:resource => { :name => 'Nested' })
      end

      it 'recursively hashes a repeated set of messages' do
        proto = Test::Nested.new(
          :multiple_resources => [
            Test::Resource.new(:name => 'Resource 1'),
            Test::Resource.new(:name => 'Resource 2'),
          ],
        )

        expect(proto.to_hash).to eq(
          :multiple_resources => [
            { :name => 'Resource 1' },
            { :name => 'Resource 2' },
          ],
        )
      end
    end

    it 'uses simple field names as keys when possible and fully qualified names otherwise' do
      message = Class.new(::Protobuf::Message) do
        optional :int32, :field, 1
        optional :int32, :colliding_field, 2
        extensions 100...200
        optional :int32, :".ext.normal_ext_field", 100, :extension => true
        optional :int32, :".ext.colliding_field", 101, :extension => true
        optional :int32, :".ext.colliding_field2", 102, :extension => true
        optional :int32, :".ext2.colliding_field2", 103, :extension => true
      end

      hash = {
        :field => 1,
        :colliding_field => 2,
        :normal_ext_field => 3,
        :".ext.colliding_field" => 4,
        :".ext.colliding_field2" => 5,
        :".ext2.colliding_field2" => 6,
      }
      instance = message.new(hash)
      expect(instance.to_hash).to eq(hash)
    end
  end

  describe '#to_json' do
    subject do
      ::Test::ResourceFindRequest.new(:name => 'Test Name', :active => false)
    end

    specify { expect(subject.to_json).to eq '{"name":"Test Name","active":false}' }

    context 'for byte fields' do
      let(:bytes) { "\x06\x8D1HP\x17:b".force_encoding(Encoding::ASCII_8BIT) }

      subject do
        ::Test::ResourceFindRequest.new(:widget_bytes => [bytes])
      end

      specify { expect(subject.to_json).to eq '{"widget_bytes":["Bo0xSFAXOmI="]}' }
    end

    context 'using proto3 produces lower case field names' do
      let(:bytes) { "\x06\x8D1HP\x17:b".force_encoding(Encoding::ASCII_8BIT) }

      subject do
        ::Test::ResourceFindRequest.new(:widget_bytes => [bytes])
      end

      specify { expect(subject.to_json(:proto3 => true)).to eq '{"widgetBytes":["Bo0xSFAXOmI="]}' }
    end
  end

  describe '.from_json' do
    it 'decodes optional bytes field with base64' do
      expected_single_bytes = "\x06\x8D1HP\x17:b".unpack('C*')
      single_bytes = ::Test::ResourceFindRequest
                     .from_json('{"singleBytes":"Bo0xSFAXOmI="}')
                     .single_bytes.unpack('C*')

      expect(single_bytes).to(eq(expected_single_bytes))
    end

    it 'decodes repeated bytes field with base64' do
      expected_widget_bytes = ["\x06\x8D1HP\x17:b"].map { |s| s.unpack('C*') }
      widget_bytes = ::Test::ResourceFindRequest
                     .from_json('{"widgetBytes":["Bo0xSFAXOmI="]}')
                     .widget_bytes.map { |s| s.unpack('C*') }

      expect(widget_bytes).to(eq(expected_widget_bytes))
    end
  end

  describe '.to_json' do
    it 'returns the class name of the message for use in json encoding' do
      expect do
        ::Timeout.timeout(0.1) do
          expect(::Test::Resource.to_json).to eq("Test::Resource")
        end
      end.not_to raise_error
    end
  end

  describe "#define_accessor" do
    subject { ::Test::Resource.new }

    it 'allows string fields to be set to nil' do
      expect { subject.name = nil }.to_not raise_error
    end

    it 'does not allow string fields to be set to Numeric' do
      expect { subject.name = 1 }.to raise_error(/name/)
    end

    it 'does not allow a repeated field is set to nil' do
      expect { subject.repeated_enum = nil }.to raise_error(TypeError)
    end

    context '#{simple_field_name}!' do
      it 'returns value of set field' do
        expect(::Test::Resource.new(:name => "Joe").name!).to eq("Joe")
      end

      it 'returns value of set field with default' do
        expect(::Test::Resource.new(:name => "").name!).to eq("")
      end

      it 'returns nil if extension field is unset' do
        expect(subject.ext_is_searchable!).to be_nil
      end

      it 'returns value of set extension field' do
        message = ::Test::Resource.new(:ext_is_searchable => true)
        expect(message.ext_is_searchable!).to be(true)
      end

      it 'returns value of set extension field with default' do
        message = ::Test::Resource.new(:ext_is_searchable => false)
        expect(message.ext_is_searchable!).to be(false)
      end

      it 'returns nil for an unset repeated field that has only be read' do
        message = ::Test::Resource.new
        expect(message.repeated_enum!).to be_nil
        message.repeated_enum
        expect(message.repeated_enum!).to be_nil
      end

      it 'returns value for an unset repeated field has been read and appended to' do
        message = ::Test::Resource.new
        message.repeated_enum << 1
        expect(message.repeated_enum!).to eq([1])
      end

      it 'returns value for an unset repeated field has been explicitly set' do
        message = ::Test::Resource.new
        message.repeated_enum = [1]
        expect(message.repeated_enum!).to eq([1])
      end
    end
  end

  describe '.get_extension_field' do
    it 'fetches an extension field by its tag' do
      field = ::Test::Resource.get_extension_field(100)
      expect(field).to be_a(::Protobuf::Field::BoolField)
      expect(field.tag).to eq(100)
      expect(field.name).to eq(:ext_is_searchable)
      expect(field.fully_qualified_name).to eq(:'.test.Searchable.ext_is_searchable')
      expect(field).to be_extension
    end

    it 'fetches an extension field by its symbolized name' do
      expect(::Test::Resource.get_extension_field(:ext_is_searchable)).to be_a(::Protobuf::Field::BoolField)
      expect(::Test::Resource.get_extension_field('ext_is_searchable')).to be_a(::Protobuf::Field::BoolField)
      expect(::Test::Resource.get_extension_field(:'.test.Searchable.ext_is_searchable')).to be_a(::Protobuf::Field::BoolField)
      expect(::Test::Resource.get_extension_field('.test.Searchable.ext_is_searchable')).to be_a(::Protobuf::Field::BoolField)
    end

    it 'returns nil when attempting to get a non-extension field' do
      expect(::Test::Resource.get_extension_field(1)).to be_nil
    end

    it 'returns nil when field is not found' do
      expect(::Test::Resource.get_extension_field(-1)).to be_nil
      expect(::Test::Resource.get_extension_field(nil)).to be_nil
    end
  end

  describe '#field?' do
    it 'returns false for non-existent field' do
      expect(::Test::Resource.get_field('doesnotexist')).to be_nil
      expect(::Test::Resource.new.field?('doesnotexist')).to be(false)
    end

    it 'returns false for unset field' do
      expect(::Test::Resource.get_field('name')).to be
      expect(::Test::Resource.new.field?('name')).to be(false)
    end

    it 'returns false for unset field from tag' do
      expect(::Test::Resource.get_field(1)).to be
      expect(::Test::Resource.new.field?(1)).to be(false)
    end

    it 'returns true for set field' do
      expect(::Test::Resource.new(:name => "Joe").field?('name')).to be(true)
    end

    it 'returns true for set field with default' do
      expect(::Test::Resource.new(:name => "").field?('name')).to be(true)
    end

    it 'returns true from field tag value' do
      expect(::Test::Resource.new(:name => "Joe").field?(1)).to be(true)
    end

    it 'returns false for unset extension field' do
      ext_field = :".test.Searchable.ext_is_searchable"
      expect(::Test::Resource.get_extension_field(ext_field)).to be
      expect(::Test::Resource.new.field?(ext_field)).to be(false)
    end

    it 'returns false for unset extension field from tag' do
      expect(::Test::Resource.get_extension_field(100)).to be
      expect(::Test::Resource.new.field?(100)).to be(false)
    end

    it 'returns true for set extension field' do
      ext_field = :".test.Searchable.ext_is_searchable"
      message = ::Test::Resource.new(ext_field => true)
      expect(message.field?(ext_field)).to be(true)
    end

    it 'returns true for set extension field with default' do
      ext_field = :".test.Searchable.ext_is_searchable"
      message = ::Test::Resource.new(ext_field => false)
      expect(message.field?(ext_field)).to be(true)
    end

    it 'returns true for set extension field from tag' do
      ext_field = :".test.Searchable.ext_is_searchable"
      message = ::Test::Resource.new(ext_field => false)
      expect(message.field?(100)).to be(true)
    end

    it 'returns false for repeated field that has been read from' do
      message = ::Test::Resource.new
      expect(message.field?(:repeated_enum)).to be(false)
      message.repeated_enum
      expect(message.field?(:repeated_enum)).to be(false)
    end

    it 'returns true for a repeated field that has been read from and appended to' do
      message = ::Test::Resource.new
      message.repeated_enum << 1
      expect(message.field?(:repeated_enum)).to be(true)
    end

    it 'returns true for a repeated field that has been set with the setter' do
      message = ::Test::Resource.new
      message.repeated_enum = [1]
      expect(message.field?(:repeated_enum)).to be(true)
    end

    it 'returns false for a repeated field that has been replaced with []' do
      message = ::Test::Resource.new
      message.repeated_enum.replace([])
      expect(message.field?(:repeated_enum)).to be(false)
    end
  end

  describe '.get_field' do
    it 'fetches a non-extension field by its tag' do
      field = ::Test::Resource.get_field(1)
      expect(field).to be_a(::Protobuf::Field::StringField)
      expect(field.tag).to eq(1)
      expect(field.name).to eq(:name)
      expect(field.fully_qualified_name).to eq(:name)
      expect(field).not_to be_extension
    end

    it 'fetches a non-extension field by its symbolized name' do
      expect(::Test::Resource.get_field(:name)).to be_a(::Protobuf::Field::StringField)
      expect(::Test::Resource.get_field('name')).to be_a(::Protobuf::Field::StringField)
    end

    it 'fetches an extension field when forced' do
      expect(::Test::Resource.get_field(100, true)).to be_a(::Protobuf::Field::BoolField)
      expect(::Test::Resource.get_field(:'.test.Searchable.ext_is_searchable', true)).to be_a(::Protobuf::Field::BoolField)
      expect(::Test::Resource.get_field('.test.Searchable.ext_is_searchable', true)).to be_a(::Protobuf::Field::BoolField)
    end

    it 'returns nil when attempting to get an extension field' do
      expect(::Test::Resource.get_field(100)).to be_nil
    end

    it 'returns nil when field is not defined' do
      expect(::Test::Resource.get_field(-1)).to be_nil
      expect(::Test::Resource.get_field(nil)).to be_nil
    end
  end

  describe 'defining a field' do
    # Case 1
    context 'single base field' do
      let(:klass) do
        Class.new(Protobuf::Message) do
          optional :string, :foo, 1
        end
      end

      it 'has an accessor for foo' do
        message = klass.new(:foo => 'bar')
        expect(message.foo).to eq('bar')
        expect(message[:foo]).to eq('bar')
        expect(message['foo']).to eq('bar')
      end
    end

    # Case 2
    context 'base field and extension field name collision' do
      let(:klass) do
        Class.new(Protobuf::Message) do
          optional :string, :foo, 1
          optional :string, :".boom.foo", 2, :extension => true
        end
      end

      it 'has an accessor for foo that refers to the base field' do
        message = klass.new(:foo => 'bar', '.boom.foo' => 'bam')
        expect(message.foo).to eq('bar')
        expect(message[:foo]).to eq('bar')
        expect(message['foo']).to eq('bar')
        expect(message[:'.boom.foo']).to eq('bam')
        expect(message['.boom.foo']).to eq('bam')
      end
    end

    # Case 3
    context 'no base field with extension fields with name collision' do
      let(:klass) do
        Class.new(Protobuf::Message) do
          optional :string, :".boom.foo", 2, :extension => true
          optional :string, :".goat.foo", 3, :extension => true
        end
      end

      it 'has an accessor for foo that refers to the extension field' do
        message = klass.new('.boom.foo' => 'bam', '.goat.foo' => 'red')
        expect { message.foo }.to raise_error(NoMethodError)
        expect { message[:foo] }.to raise_error(ArgumentError)
        expect { message['foo'] }.to raise_error(ArgumentError)
        expect(message[:'.boom.foo']).to eq('bam')
        expect(message['.boom.foo']).to eq('bam')
        expect(message[:'.goat.foo']).to eq('red')
        expect(message['.goat.foo']).to eq('red')
      end
    end

    # Case 4
    context 'no base field with an extension field' do
      let(:klass) do
        Class.new(Protobuf::Message) do
          optional :string, :".boom.foo", 2, :extension => true
        end
      end

      it 'has an accessor for foo that refers to the extension field' do
        message = klass.new('.boom.foo' => 'bam')
        expect(message.foo).to eq('bam')
        expect(message[:foo]).to eq('bam')
        expect(message['foo']).to eq('bam')
        expect(message[:'.boom.foo']).to eq('bam')
        expect(message['.boom.foo']).to eq('bam')
      end
    end
  end

  describe 'map fields' do
    it 'serializes the same as equivalent non-map-field' do
      class MessageWithMapField < ::Protobuf::Message
        map :int32, :string, :map, 1
      end

      class MessageWithoutMapField < ::Protobuf::Message
        class MapEntry < ::Protobuf::Message
          optional :int32, :key, 1
          optional :string, :value, 2
        end
        repeated MapEntry, :map, 1
      end

      map_msg = MessageWithMapField.new(:map =>
        {
          1 => 'one',
          2 => 'two',
          3 => 'three',
          4 => 'four',
        })
      mapless_msg = MessageWithoutMapField.new(:map =>
        [{ :key => 1, :value => 'one' },
         { :key => 2, :value => 'two' },
         { :key => 3, :value => 'three' },
         { :key => 4, :value => 'four' },
        ])

      map_bytes = map_msg.encode
      mapless_bytes = mapless_msg.encode
      expect(map_bytes).to eq(mapless_bytes)

      expect(MessageWithMapField.decode(mapless_bytes)).to eq(map_msg)
      expect(MessageWithoutMapField.decode(map_bytes)).to eq(mapless_msg)
    end
  end

  describe '.[]=' do
    context 'clearing fields' do
      it 'clears repeated fields with an empty array' do
        instance = ::Test::Resource.new(:repeated_enum => [::Test::StatusType::ENABLED])
        expect(instance.field?(:repeated_enum)).to be(true)
        instance[:repeated_enum] = []
        expect(instance.field?(:repeated_enum)).to be(false)
      end

      it 'clears optional fields with nil' do
        instance = ::Test::Resource.new(:name => "Joe")
        expect(instance.field?(:name)).to be(true)
        instance[:name] = nil
        expect(instance.field?(:name)).to be(false)
      end

      it 'clears optional extenstion fields with nil' do
        instance = ::Test::Resource.new(:ext_is_searchable => true)
        expect(instance.field?(:ext_is_searchable)).to be(true)
        instance[:ext_is_searchable] = nil
        expect(instance.field?(:ext_is_searchable)).to be(false)
      end
    end

    context 'setting fields' do
      let(:instance) { ::Test::Resource.new }

      it 'sets and replaces repeated fields' do
        initial = [::Test::StatusType::ENABLED, ::Test::StatusType::DISABLED]
        instance[:repeated_enum] = initial
        expect(instance[:repeated_enum]).to eq(initial)
        replacement = [::Test::StatusType::DELETED]
        instance[:repeated_enum] = replacement
        expect(instance[:repeated_enum]).to eq(replacement)
      end

      it 'sets acceptable optional field values' do
        instance[:name] = "Joe"
        expect(instance[:name]).to eq("Joe")
        instance[1] = "Tom"
        expect(instance[:name]).to eq("Tom")
      end

      it 'sets acceptable empty string field values' do
        instance[:name] = ""
        expect(instance.name!).to eq("")
      end

      it 'sets acceptable empty message field values' do
        instance = ::Test::Nested.new
        instance[:resource] = {}
        expect(instance.resource!).to eq(::Test::Resource.new)
      end

      it 'sets acceptable extension field values' do
        instance[:ext_is_searchable] = true
        expect(instance[:ext_is_searchable]).to eq(true)
        instance[:".test.Searchable.ext_is_searchable"] = false
        expect(instance[:ext_is_searchable]).to eq(false)
        instance[100] = true
        expect(instance[:ext_is_searchable]).to eq(true)
      end

      # to be deprecated
      it 'does nothing when sent an empty array' do
        instance[:repeated_enum] = nil
        expect(instance[:repeated_enum]).to eq([])
        instance[:repeated_enum] = [1, 2]
        expect(instance[:repeated_enum]).to eq([1, 2])
        instance[:repeated_enum] = nil
        # Yes this is very silly, but backwards compatible
        expect(instance[:repeated_enum]).to eq([1, 2])
      end
    end

    context 'throwing TypeError' do
      let(:instance) { ::Test::Resource.new }

      it 'throws when a repeated value is set with a non array' do
        expect { instance[:repeated_enum] = "string" }.to raise_error(TypeError)
      end

      it 'throws when a repeated value is set with an array of the wrong type' do
        expect { instance[:repeated_enum] = [true, false] }.to raise_error(TypeError)
      end

      it 'throws when an optional value is not #acceptable?' do
        expect { instance[:name] = 1 }.to raise_error(TypeError)
      end
    end

    context 'ignoring unknown fields' do
      around do |example|
        orig = ::Protobuf.ignore_unknown_fields?
        ::Protobuf.ignore_unknown_fields = true
        example.call
        ::Protobuf.ignore_unknown_fields = orig
      end

      context 'with valid fields' do
        let(:values) { { :name => "Jim" } }

        it "does not raise an error" do
          expect { ::Test::Resource.new(values) }.to_not raise_error
        end
      end

      context 'with non-existent field' do
        let(:values) { { :name => "Jim", :othername => "invalid" } }

        it "does not raise an error" do
          expect { ::Test::Resource.new(values) }.to_not raise_error
        end
      end
    end

    context 'not ignoring unknown fields' do
      around do |example|
        orig = ::Protobuf.ignore_unknown_fields?
        ::Protobuf.ignore_unknown_fields = false
        example.call
        ::Protobuf.ignore_unknown_fields = orig
      end

      context 'with valid fields' do
        let(:values) { { :name => "Jim" } }

        it "does not raise an error" do
          expect { ::Test::Resource.new(values) }.to_not raise_error
        end
      end

      context 'with non-existent field' do
        let(:values) { { :name => "Jim", :othername => "invalid" } }

        it "raises an error and mentions the erroneous field" do
          expect { ::Test::Resource.new(values) }.to raise_error(::Protobuf::FieldNotDefinedError, /othername/)
        end

        context 'with a nil value' do
          let(:values) { { :name => "Jim", :othername => nil } }

          it "raises an error and mentions the erroneous field" do
            expect { ::Test::Resource.new(values) }.to raise_error(::Protobuf::FieldNotDefinedError, /othername/)
          end
        end
      end
    end
  end
end
