require 'spec_helper'
require SUPPORT_PATH.join('resource_service')

RSpec.describe 'works through class inheritance' do
  module Corp
    module Protobuf
      class Error < ::Protobuf::Message
        required :string, :foo, 1
      end
    end
  end
  module Corp
    class ErrorHandler < Corp::Protobuf::Error
    end
  end

  let(:args) { { :foo => 'bar' } }
  let(:parent_class) { Corp::Protobuf::Error }
  let(:inherited_class) { Corp::ErrorHandler }

  specify '#encode' do
    expected_result = "\n\x03bar"
    expected_result.force_encoding(Encoding::BINARY)
    expect(parent_class.new(args).encode).to eq(expected_result)
    expect(inherited_class.new(args).encode).to eq(expected_result)
  end

  specify '#to_hash' do
    expect(parent_class.new(args).to_hash).to eq(args)
    expect(inherited_class.new(args).to_hash).to eq(args)
  end

  specify '#to_json' do
    expect(parent_class.new(args).to_json).to eq(args.to_json)
    expect(inherited_class.new(args).to_json).to eq(args.to_json)
  end

  specify '.encode' do
    expected_result = "\n\x03bar"
    expected_result.force_encoding(Encoding::BINARY)
    expect(parent_class.encode(args)).to eq(expected_result)
    expect(inherited_class.encode(args)).to eq(expected_result)
  end

  specify '.decode' do
    raw_value = "\n\x03bar"
    raw_value.force_encoding(Encoding::BINARY)
    expect(parent_class.decode(raw_value).to_hash).to eq(args)
    expect(inherited_class.decode(raw_value).to_hash).to eq(args)
  end

end
