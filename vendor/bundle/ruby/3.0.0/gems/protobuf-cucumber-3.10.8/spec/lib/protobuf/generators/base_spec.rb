require 'spec_helper'

require 'protobuf/code_generator'
require 'protobuf/generators/base'

RSpec.describe ::Protobuf::Generators::Base do

  subject(:generator) { described_class.new(double) }

  context 'namespaces' do
    let(:descriptor) { double(:name => 'Baz') }
    subject { described_class.new(descriptor, 0, :namespace => [:foo, :bar]) }
    specify { expect(subject.type_namespace).to eq([:foo, :bar, 'Baz']) }
    specify { expect(subject.fully_qualified_type_namespace).to eq('.foo.bar.Baz') }
  end

  describe '#run_once' do
    it 'protects the block from being entered more than once' do
      foo = 0
      bar = 0

      test_run_once = lambda do
        bar += 1
        subject.run_once(:foo_test) do
          foo += 1
        end
      end

      10.times { test_run_once.call }
      expect(foo).to eq(1)
      expect(bar).to eq(10)
    end

    it 'always returns the same object' do
      rv = subject.run_once(:foo_test) do
        "foo bar"
      end
      expect(rv).to eq("foo bar")

      rv = subject.run_once(:foo_test) do
        "baz quux"
      end
      expect(rv).to eq("foo bar")
    end
  end

  describe '#to_s' do
    before do
      class ToStringTest < ::Protobuf::Generators::Base
        def compile
          run_once(:compile) do
            puts "this is a test"
          end
        end
      end
    end

    subject { ToStringTest.new(double) }

    it 'compiles and returns the contents' do
      10.times do
        expect(subject.to_s).to eq("this is a test\n")
      end
    end
  end

  describe '#validate_tags' do
    context 'when tags are duplicated' do
      it 'fails with a GeneratorFatalError' do
        expect(::Protobuf::CodeGenerator).to receive(:fatal).with(/FooBar object has duplicate tags\. Expected 3 tags, but got 4/)
        described_class.validate_tags("FooBar", [1, 2, 2, 3])
      end
    end

    context 'when tags are missing in the range' do
      it 'prints a warning' do
        allow(ENV).to receive(:key?).and_call_original
        allow(ENV).to receive(:key?).with("PB_NO_TAG_WARNINGS").and_return(false)
        expect(::Protobuf::CodeGenerator).to receive(:print_tag_warning_suppress)
        expect(::Protobuf::CodeGenerator).to receive(:warn).with(/FooBar object should have 5 tags \(1\.\.5\), but found 4 tags/)
        described_class.validate_tags("FooBar", [1, 2, 4, 5])
      end
    end
  end

  describe '#serialize_value' do
    before do
      stub_const("MyEnum", Class.new(::Protobuf::Enum) do
        define :FOO, 1
        define :BOO, 2
      end)
      stub_const("MyMessage1", Class.new(Protobuf::Message) do
        optional :string, :foo, 1
      end)
      stub_const("MyMessage2", Class.new(Protobuf::Message) do
        optional :string, :foo, 1
        optional MyMessage1, :bar, 2
        optional :int32, :boom, 3
        optional MyEnum, :goat, 4
        optional :bool, :bam, 5
        optional :float, :fire, 6
      end)
      stub_const("MyMessage3", Class.new(Protobuf::Message) do
        optional :string, :foo, 1
        repeated MyMessage2, :bar, 2
        optional :int32, :boom, 3
        optional MyEnum, :goat, 4
        optional :bool, :bam, 5
        optional :float, :fire, 6
      end)
    end

    it 'serializes messages' do
      output_string = <<-STRING
        { :foo => "space",
          :bar => [{
            :foo => "station",
            :bar => { :foo => "orbit" },
            :boom => 123,
            :goat => ::MyEnum::FOO,
            :bam => false,
            :fire => 3.5 }],
          :boom => 456,
          :goat => ::MyEnum::BOO,
          :bam => true, :fire => 1.2 }
      STRING

      output_string.lstrip!
      output_string.rstrip!
      output_string.delete!("\n")
      output_string.squeeze!(" ")
      expect(generator.serialize_value(MyMessage3.new(
                                         :foo => 'space',
                                         :bar => [MyMessage2.new(
                                           :foo => 'station',
                                           :bar => MyMessage1.new(:foo => 'orbit'),
                                           :boom => 123,
                                           :goat => MyEnum::FOO,
                                           :bam => false,
                                           :fire => 3.5,
                                         )],
                                         :boom => 456,
                                         :goat => MyEnum::BOO,
                                         :bam => true,
                                         :fire => 1.2,
      ))).to eq(output_string)
    end

    it 'serializes enums' do
      expect(generator.serialize_value(MyEnum::FOO)).to eq("::MyEnum::FOO")
      expect(generator.serialize_value(MyEnum::BOO)).to eq("::MyEnum::BOO")
    end
  end
end
