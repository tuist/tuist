require 'spec_helper'

require 'protobuf/code_generator'

RSpec.describe ::Protobuf::CodeGenerator do

  # Some constants to shorten things up
  DESCRIPTOR = ::Google::Protobuf
  COMPILER = ::Google::Protobuf::Compiler

  describe '#response_bytes' do
    let(:input_file1) { DESCRIPTOR::FileDescriptorProto.new(:name => 'test/foo.proto') }
    let(:input_file2) { DESCRIPTOR::FileDescriptorProto.new(:name => 'test/bar.proto') }

    let(:output_file1) { COMPILER::CodeGeneratorResponse::File.new(:name => 'test/foo.pb.rb') }
    let(:output_file2) { COMPILER::CodeGeneratorResponse::File.new(:name => 'test/bar.pb.rb') }

    let(:file_generator1) { double('file generator 1', :generate_output_file => output_file1) }
    let(:file_generator2) { double('file generator 2', :generate_output_file => output_file2) }

    let(:request_bytes) do
      COMPILER::CodeGeneratorRequest.encode(:proto_file => [input_file1, input_file2])
    end

    let(:expected_response_bytes) do
      COMPILER::CodeGeneratorResponse.encode(:file => [output_file1, output_file2])
    end

    before do
      expect(::Protobuf::Generators::FileGenerator).to receive(:new).with(input_file1).and_return(file_generator1)
      expect(::Protobuf::Generators::FileGenerator).to receive(:new).with(input_file2).and_return(file_generator2)
    end

    it 'returns the serialized CodeGeneratorResponse which contains the generated file contents' do
      generator = described_class.new(request_bytes)
      expect(generator.response_bytes).to eq expected_response_bytes
    end
  end

  describe '#eval_unknown_extensions' do
    let(:input_file) do
      DESCRIPTOR::FileDescriptorProto.new(
        :name => 'test/boom.proto',
        :package => 'test.pkg.code_generator_spec',
        :extension => [{
          :name => 'boom',
          :number => 20100,
          :label => Google::Protobuf::FieldDescriptorProto::Label::LABEL_OPTIONAL,
          :type => Google::Protobuf::FieldDescriptorProto::Type::TYPE_STRING,
          :extendee => '.google.protobuf.FieldOptions',
        }],
      )
    end
    let(:request_bytes) { COMPILER::CodeGeneratorRequest.encode(:proto_file => [input_file]) }

    it 'evals files as they are generated' do
      described_class.new(request_bytes).eval_unknown_extensions!
      expect(Google::Protobuf::FieldOptions.extension_fields.map(&:fully_qualified_name)).to include(:'.test.pkg.code_generator_spec.boom')
      expect(Google::Protobuf::FieldOptions.extension_fields.map(&:name)).to include(:boom)
      added_extension = Google::Protobuf::FieldOptions.extension_fields.detect { |f| f.fully_qualified_name == :'.test.pkg.code_generator_spec.boom' }
      expect(added_extension.name).to eq(:boom)
      expect(added_extension.rule).to eq(:optional)
      expect(added_extension.type_class).to eq(::Protobuf::Field::StringField)
      expect(added_extension.tag).to eq(20100)
    end
  end

  context 'class-level printing methods' do
    describe '.fatal' do
      it 'raises a CodeGeneratorFatalError error' do
        expect do
          described_class.fatal("something is wrong")
        end.to raise_error(
          ::Protobuf::CodeGenerator::CodeGeneratorFatalError,
          "something is wrong",
        )
      end
    end

    describe '.warn' do
      it 'prints a warning to stderr' do
        expect(STDERR).to receive(:puts).with("[WARN] a warning")
        described_class.warn("a warning")
      end
    end
  end
end
