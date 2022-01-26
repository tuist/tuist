require 'base64'
require 'spec_helper'

RSpec.describe Protobuf::Varint do
  VALUES = {
    0 => "AA==",
    5 => "BQ==",
    51 => "Mw==",
    9_192 => "6Ec=",
    80_389 => "hfQE",
    913_389 => "7d83",
    516_192_829_912_693 => "9eyMkpivdQ==",
    9_999_999_999_999_999_999 => "//+fz8jgyOOKAQ==",
  }.freeze

  [defined?(::Varint) ? ::Varint : nil, Protobuf::VarintPure].compact.each do |klass|
    context "with #{klass}" do
      before { described_class.extend(klass) }
      after { load ::File.expand_path('../../../../lib/protobuf/varint.rb', __FILE__) }

      VALUES.each do |number, encoded|
        it "decodes #{number}" do
          io = StringIO.new(Base64.decode64(encoded))
          expect(described_class.decode(io)).to eq(number)
        end
      end
    end
  end
end
