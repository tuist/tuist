require 'spec_helper'

RSpec.describe Protobuf::Field::Sfixed32Field do

  it_behaves_like :packable_field, described_class do
    let(:value) { [-1, 0, 1] }
  end

end
