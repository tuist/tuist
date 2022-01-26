require 'spec_helper'

require 'protobuf/generators/enum_generator'

RSpec.describe ::Protobuf::Generators::EnumGenerator do

  let(:values) do
    [
      { :name => 'FOO', :number => 1 },
      { :name => 'BAR', :number => 2 },
      { :name => 'BAZ', :number => 3 },
    ]
  end
  let(:options) { nil }
  let(:enum_fields) do
    {
      :name => 'TestEnum',
      :value => values,
      :options => options,
    }
  end

  let(:enum) { ::Google::Protobuf::EnumDescriptorProto.new(enum_fields) }

  subject { described_class.new(enum) }

  describe '#compile' do
    let(:compiled) do
      <<-RUBY
class TestEnum < ::Protobuf::Enum
  define :FOO, 1
  define :BAR, 2
  define :BAZ, 3
end

      RUBY
    end

    it 'compiles the enum and its field values' do
      subject.compile
      expect(subject.to_s).to eq(compiled)
    end

    context 'when allow_alias option is set' do
      let(:compiled) do
        <<-RUBY
class TestEnum < ::Protobuf::Enum
  set_option :allow_alias, true

  define :FOO, 1
  define :BAR, 2
  define :BAZ, 3
end

        RUBY
      end

      let(:options) { { :allow_alias => true } }

      it 'sets the allow_alias option' do
        subject.compile
        expect(subject.to_s).to eq(compiled)
      end
    end
  end

  describe '#build_value' do
    it 'returns a string identifying the given enum value' do
      expect(subject.build_value(enum.value.first)).to eq("define :FOO, 1")
    end

    context 'with PB_UPCASE_ENUMS set' do
      before { allow(ENV).to receive(:key?).with('PB_UPCASE_ENUMS').and_return(true) }
      let(:values) { [{ :name => 'boom', :number => 1 }] }

      it 'returns a string with the given enum name in ALL CAPS' do
        expect(subject.build_value(enum.value.first)).to eq("define :BOOM, 1")
      end
    end
  end

end
