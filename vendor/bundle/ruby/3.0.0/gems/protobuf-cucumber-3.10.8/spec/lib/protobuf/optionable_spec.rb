require 'spec_helper'
require 'protobuf/optionable'
require 'protobuf/field/message_field'
require PROTOS_PATH.join('resource.pb')

RSpec.describe 'Optionable' do
  describe '.{get,get!}_option' do
    before do
      stub_const("OptionableGetOptionTest", Class.new(::Protobuf::Message) do
        set_option :deprecated, true
        set_option :".package.message_field", :field => 33

        optional :int32, :field, 1
      end)
    end

    it '.get_option retrieves the option as a symbol' do
      expect(OptionableGetOptionTest.get_option(:deprecated)).to be(true)
    end

    it '.get_option returns the default value for unset options' do
      expect(OptionableGetOptionTest.get_option(:message_set_wire_format)).to be(false)
    end

    it '.get_option retrieves the option as a string' do
      expect(OptionableGetOptionTest.get_option('deprecated')).to be(true)
    end

    it '.get_option errors if the option does not exist' do
      expect { OptionableGetOptionTest.get_option(:baz) }.to raise_error(ArgumentError)
    end

    it '.get_option errors if the option is not accessed by its fully qualified name' do
      message_field = ::Protobuf::Field::MessageField.new(
        OptionableGetOptionTest, :optional, OptionableGetOptionTest, '.package.message_field', 2, '.message_field', {})
      allow(::Google::Protobuf::MessageOptions).to receive(:get_field).and_return(message_field)
      expect { OptionableGetOptionTest.get_option(message_field.name) }.to raise_error(ArgumentError)
    end

    it '.get_option can return an option representing a message' do
      message_field = ::Protobuf::Field::MessageField.new(
        OptionableGetOptionTest, :optional, OptionableGetOptionTest, '.package.message_field', 2, 'message_field', {})
      allow(::Google::Protobuf::MessageOptions).to receive(:get_field).and_return(message_field)
      expect(OptionableGetOptionTest.get_option(message_field.fully_qualified_name)).to eq(OptionableGetOptionTest.new(:field => 33))
    end

    it '.get_option! retrieves explicitly an set option' do
      expect(OptionableGetOptionTest.get_option!(:deprecated)).to be(true)
    end

    it '.get_option! returns nil for unset options' do
      expect(OptionableGetOptionTest.get_option!(:message_set_wire_format)).to be(nil)
    end

    it '.get_option! errors if the option does not exist' do
      expect { OptionableGetOptionTest.get_option(:baz) }.to raise_error(ArgumentError)
    end

    it '#get_option retrieves the option as a symbol' do
      expect(OptionableGetOptionTest.new.get_option(:deprecated)).to be(true)
    end

    it '#get_option returns the default value for unset options' do
      expect(OptionableGetOptionTest.new.get_option(:message_set_wire_format)).to be(false)
    end

    it '#get_option retrieves the option as a string' do
      expect(OptionableGetOptionTest.new.get_option('deprecated')).to be(true)
    end

    it '#get_option errors if the option is not accessed by its fully qualified name' do
      message_field = ::Protobuf::Field::MessageField.new(
        OptionableGetOptionTest, :optional, OptionableGetOptionTest, '.package.message_field', 2, 'message_field', {})
      allow(::Google::Protobuf::MessageOptions).to receive(:get_field).and_return(message_field)
      expect { OptionableGetOptionTest.new.get_option(message_field.name) }.to raise_error(ArgumentError)
    end

    it '#get_option can return an option representing a message' do
      message_field = ::Protobuf::Field::MessageField.new(
        OptionableGetOptionTest, :optional, OptionableGetOptionTest, '.package.message_field', 2, 'message_field', {})
      allow(::Google::Protobuf::MessageOptions).to receive(:get_field).and_return(message_field)
      expect(OptionableGetOptionTest.new.get_option(message_field.fully_qualified_name)).to eq(OptionableGetOptionTest.new(:field => 33))
    end

    it '#get_option errors if the option does not exist' do
      expect { OptionableGetOptionTest.new.get_option(:baz) }.to raise_error(ArgumentError)
    end

    it '#get_option! retrieves explicitly an set option' do
      expect(OptionableGetOptionTest.new.get_option!(:deprecated)).to be(true)
    end

    it '#get_option! returns nil for unset options' do
      expect(OptionableGetOptionTest.new.get_option!(:message_set_wire_format)).to be(nil)
    end

    it '#get_option! errors if the option does not exist' do
      expect { OptionableGetOptionTest.new.get_option(:baz) }.to raise_error(ArgumentError)
    end
  end

  describe '.inject' do
    let(:klass) { Class.new }

    it 'adds klass.{set,get}_option' do
      expect { klass.get_option(:deprecated) }.to raise_error(NoMethodError)
      expect { klass.__send__(:set_option, :deprecated, true) }.to raise_error(NoMethodError)
      ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::MessageOptions }
      expect(klass.get_option(:deprecated)).to eq(false)
      expect { klass.set_option(:deprecated, true) }.to raise_error(NoMethodError)
      klass.__send__(:set_option, :deprecated, true)
      expect(klass.get_option(:deprecated)).to eq(true)
    end

    it 'adds klass#get_option' do
      expect { klass.new.get_option(:deprecated) }.to raise_error(NoMethodError)
      ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::MessageOptions }
      expect(klass.new.get_option(:deprecated)).to eq(false)
    end

    it 'adds klass.optionable_descriptor_class' do
      expect { klass.optionable_descriptor_class }.to raise_error(NoMethodError)
      ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::MessageOptions }
      expect(klass.optionable_descriptor_class).to eq(::Google::Protobuf::MessageOptions)
    end

    it 'does not add klass.optionable_descriptor_class twice' do
      expect(klass).to receive(:define_singleton_method).once
      ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::MessageOptions }
      klass.instance_eval do
        def optionable_descriptor_class
          ::Google::Protobuf::MessageOptions
        end
      end
      ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::MessageOptions }
    end

    it 'throws error when klass.optionable_descriptor_class defined twice with different args' do
      ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::MessageOptions }
      expect { ::Protobuf::Optionable.inject(klass) { ::Google::Protobuf::FileOptions } }
        .to raise_error('A class is being defined with two different descriptor classes, something is very wrong')
    end

    context 'extend_class = false' do
      let(:object) { klass.new }
      it 'adds object.{get,set}_option' do
        expect { object.get_option(:deprecated) }.to raise_error(NoMethodError)
        expect { object.__send__(:set_option, :deprecated, true) }.to raise_error(NoMethodError)
        ::Protobuf::Optionable.inject(klass, false) { ::Google::Protobuf::MessageOptions }
        expect(object.get_option(:deprecated)).to eq(false)
        expect { object.set_option(:deprecated, true) }.to raise_error(NoMethodError)
        object.__send__(:set_option, :deprecated, true)
        expect(object.get_option(:deprecated)).to eq(true)
      end

      it 'does not add klass.{get,set}_option' do
        expect { object.get_option(:deprecated) }.to raise_error(NoMethodError)
        ::Protobuf::Optionable.inject(klass, false) { ::Google::Protobuf::MessageOptions }
        expect { klass.get_option(:deprecated) }.to raise_error(NoMethodError)
        expect { klass.__send__(:set_option, :deprecated) }.to raise_error(NoMethodError)
      end

      it 'creates an instance method optionable_descriptor_class' do
        expect { object.optionable_descriptor_class }.to raise_error(NoMethodError)
        ::Protobuf::Optionable.inject(klass, false) { ::Google::Protobuf::MessageOptions }
        expect(object.optionable_descriptor_class).to eq(::Google::Protobuf::MessageOptions)
      end
    end
  end

  describe 'getting options from generated code' do
    context 'file options' do
      it 'gets base options' do
        expect(::Test.get_option!(:cc_generic_services)).to eq(true)
      end

      it 'gets unset options' do
        expect(::Test.get_option!(:java_multiple_files)).to eq(nil)
        expect(::Test.get_option(:java_multiple_files)).to eq(false)
      end

      it 'gets custom options' do
        expect(::Test.get_option!(:".test.file_option")).to eq(9876543210)
      end
    end

    context 'field options' do
      subject { ::Test::Resource.fields[0] }

      it 'gets base options' do
        expect(subject.get_option!(:ctype))
          .to eq(::Google::Protobuf::FieldOptions::CType::CORD)
      end

      it 'gets unset options' do
        expect(subject.get_option!(:lazy)).to eq(nil)
        expect(subject.get_option(:lazy)).to eq(false)
      end

      it 'gets custom options' do
        expect(subject.get_option!(:".test.field_option")).to eq(8765432109)
      end
    end

    context 'enum options' do
      subject { ::Test::StatusType }

      it 'gets base options' do
        expect(subject.get_option!(:allow_alias)).to eq(true)
      end

      it 'gets unset options' do
        expect(subject.get_option!(:deprecated)).to eq(nil)
        expect(subject.get_option(:deprecated)).to eq(false)
      end

      it 'gets custom options' do
        expect(subject.get_option!(:".test.enum_option")).to eq(-789)
      end
    end

    context 'message options' do
      subject { ::Test::Resource }

      it 'gets base options' do
        expect(subject.get_option!(:map_entry)).to eq(false)
      end

      it 'gets unset options' do
        expect(subject.get_option!(:deprecated)).to eq(nil)
        expect(subject.get_option(:deprecated)).to eq(false)
      end

      it 'gets custom options' do
        expect(subject.get_option!(:".test.message_option")).to eq(-56)
      end
    end

    context 'service options' do
      subject { ::Test::ResourceService }

      it 'gets unset options' do
        expect(subject.get_option!(:deprecated)).to eq(nil)
        expect(subject.get_option(:deprecated)).to eq(false)
      end

      it 'gets custom options' do
        expect(subject.get_option!(:".test.service_option")).to eq(-9876543210)
      end
    end

    context 'method options' do
      subject { ::Test::ResourceService.rpcs[:find] }

      it 'gets unset options' do
        expect(subject.get_option!(:deprecated)).to eq(nil)
        expect(subject.get_option(:deprecated)).to eq(false)
      end

      it 'gets custom options' do
        expect(subject.get_option!(:".test.method_option")).to eq(2)
      end
    end
  end
end
