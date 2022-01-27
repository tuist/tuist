require 'spec_helper'

RSpec.describe Protobuf::Field::DoubleField do

  it_behaves_like :packable_field, described_class do
    let(:value) { [1.0, 2.0, 3.0] }
  end

end
