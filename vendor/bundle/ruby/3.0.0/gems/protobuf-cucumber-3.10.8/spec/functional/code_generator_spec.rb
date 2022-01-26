# encoding: binary

require 'spec_helper'
require 'protobuf/code_generator'

RSpec.describe 'code generation' do
  it "generates code for google's unittest.proto" do
    bytes = IO.read(PROTOS_PATH.join('google_unittest.bin'), :mode => 'rb')

    expected_files =
      ["google_unittest_import_public.pb.rb", "google_unittest_import.pb.rb", "google_unittest.pb.rb"]

    expected_file_descriptors = expected_files.map do |file_name|
      file_content = File.open(PROTOS_PATH.join(file_name), "r:UTF-8", &:read)
      ::Google::Protobuf::Compiler::CodeGeneratorResponse::File.new(
        :name => "protos/" + file_name, :content => file_content)
    end

    expected_output =
      ::Google::Protobuf::Compiler::CodeGeneratorResponse.encode(:file => expected_file_descriptors)

    code_generator = ::Protobuf::CodeGenerator.new(bytes)
    code_generator.eval_unknown_extensions!
    expect(code_generator.response_bytes).to eq(expected_output)
  end

  it "generates code for map types" do
    input_descriptor = ::Google::Protobuf::FileDescriptorSet.decode(
      IO.read(PROTOS_PATH.join('map-test.bin'), :mode => 'rb'))
    request = ::Google::Protobuf::Compiler::CodeGeneratorRequest.new(:file_to_generate => ['map-test.proto'],
                                                                     :proto_file => input_descriptor.file)

    file_name = "map-test.pb.rb"
    file_content = File.open(PROTOS_PATH.join(file_name), "r:UTF-8", &:read)
    expected_file_output =
      ::Google::Protobuf::Compiler::CodeGeneratorResponse::File.new(
        :name => file_name, :content => file_content)

    expected_response =
      ::Google::Protobuf::Compiler::CodeGeneratorResponse.encode(:file => [expected_file_output])

    code_generator = ::Protobuf::CodeGenerator.new(request.encode)
    code_generator.eval_unknown_extensions!
    expect(code_generator.response_bytes).to eq(expected_response)
  end

  it "generates code (including service stubs) with custom field and method options" do
    expected_unittest_custom_options =
      File.open(PROTOS_PATH.join('google_unittest_custom_options.pb.rb'), "r:UTF-8", &:read)

    bytes = IO.read(PROTOS_PATH.join('google_unittest_custom_options.bin'), :mode => 'rb')
    code_generator = ::Protobuf::CodeGenerator.new(bytes)
    code_generator.eval_unknown_extensions!
    response = ::Google::Protobuf::Compiler::CodeGeneratorResponse.decode(code_generator.response_bytes)
    expect(response.file.find { |f| f.name == 'protos/google_unittest_custom_options.pb.rb' }.content)
      .to eq(expected_unittest_custom_options)
  end
end
