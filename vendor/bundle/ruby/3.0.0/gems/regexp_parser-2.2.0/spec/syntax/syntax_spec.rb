require 'spec_helper'

RSpec.describe(Regexp::Syntax) do
  specify('unknown name') do
    expect { Regexp::Syntax.new('ruby/1.0') }.to raise_error(Regexp::Syntax::UnknownSyntaxNameError)
  end

  specify('new') do
    expect(Regexp::Syntax.new('ruby/1.9.3')).to be_instance_of(Regexp::Syntax::V1_9_3)
  end

  specify('new any') do
    expect(Regexp::Syntax.new('any')).to be_instance_of(Regexp::Syntax::Any)
    expect(Regexp::Syntax.new('*')).to be_instance_of(Regexp::Syntax::Any)
  end

  specify('not implemented') do
    expect { RP.parse('\\p{alpha}', 'ruby/1.8') }.to raise_error(Regexp::Syntax::NotImplementedError)
  end

  specify('supported?') do
    expect(Regexp::Syntax.supported?('ruby/1.1.1')).to be false
    expect(Regexp::Syntax.supported?('ruby/2.4.3')).to be true
    expect(Regexp::Syntax.supported?('ruby/2.5')).to be true
  end

  specify('invalid version') do
    expect { Regexp::Syntax.version_class('2.0.0') }.to raise_error(Regexp::Syntax::InvalidVersionNameError)

    expect { Regexp::Syntax.version_class('ruby/20') }.to raise_error(Regexp::Syntax::InvalidVersionNameError)
  end

  specify('version class tiny version') do
    expect(Regexp::Syntax.version_class('ruby/1.9.3')).to eq Regexp::Syntax::V1_9_3

    expect(Regexp::Syntax.version_class('ruby/2.3.1')).to eq Regexp::Syntax::V2_3_1
  end

  specify('version class minor version') do
    expect(Regexp::Syntax.version_class('ruby/1.9')).to eq Regexp::Syntax::V1_9

    expect(Regexp::Syntax.version_class('ruby/2.3')).to eq Regexp::Syntax::V2_3
  end

  specify('raises for unknown constant lookups') do
    expect { Regexp::Syntax::V1 }.to raise_error(/V1/)
  end
end
