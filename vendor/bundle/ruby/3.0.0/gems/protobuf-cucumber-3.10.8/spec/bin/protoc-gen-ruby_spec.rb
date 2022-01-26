require 'spec_helper'

require 'protobuf/code_generator'

RSpec.describe 'protoc-gen-ruby' do
  let(:binpath) { ::File.expand_path('../../../bin/protoc-gen-ruby', __FILE__) }
  let(:package) { 'test' }
  let(:request_bytes) do
    ::Google::Protobuf::Compiler::CodeGeneratorRequest.encode(
      :proto_file => [{ :package => package }],
    )
  end

  it 'reads the serialized request bytes and outputs serialized response bytes' do
    ::IO.popen(binpath, 'w+') do |pipe|
      pipe.write(request_bytes)
      pipe.close_write # needed so we can implicitly read until EOF
      response_bytes = pipe.read
      response = ::Google::Protobuf::Compiler::CodeGeneratorResponse.decode(response_bytes)
      expect(response.file.first.content).to include("module #{package.titleize}")
    end
  end
end
