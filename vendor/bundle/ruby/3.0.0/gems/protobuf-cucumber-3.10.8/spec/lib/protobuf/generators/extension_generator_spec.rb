require 'spec_helper'

require 'protobuf/code_generator'
require 'protobuf/generators/extension_generator'

RSpec.describe ::Protobuf::Generators::ExtensionGenerator do

  let(:field_descriptors) do
    [
      double('field descriptor 1', :to_s => "  field 1\n"),
      double('field descriptor 2', :to_s => "  field 2\n"),
      double('field descriptor 3', :to_s => "  field 3\n"),
    ]
  end
  let(:message_type) { 'FooBar' }

  before do
    expect(::Protobuf::Generators::FieldGenerator).to receive(:new).with(field_descriptors[0], nil, 1).and_return(field_descriptors[0])
    expect(::Protobuf::Generators::FieldGenerator).to receive(:new).with(field_descriptors[1], nil, 1).and_return(field_descriptors[1])
    expect(::Protobuf::Generators::FieldGenerator).to receive(:new).with(field_descriptors[2], nil, 1).and_return(field_descriptors[2])
  end

  subject { described_class.new(message_type, field_descriptors, 0) }

  describe '#compile' do
    let(:compiled) do
      'class FooBar < ::Protobuf::Message
  field 1
  field 2
  field 3
end

'
    end

    it 'compiles the a class with the extension fields' do
      subject.compile
      expect(subject.to_s).to eq(compiled)
    end
  end

end
