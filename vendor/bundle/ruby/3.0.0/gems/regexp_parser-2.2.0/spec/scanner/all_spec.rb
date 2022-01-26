require 'spec_helper'

RSpec.describe(Regexp::Scanner) do
  specify('scanner returns an array') do
    expect(RS.scan('abc')).to be_instance_of(Array)
  end

  specify('scanner returns tokens as arrays') do
    tokens = RS.scan('^abc+[^one]{2,3}\\b\\d\\\\C-C$')
    expect(tokens).to all(be_a Array)
    expect(tokens.map(&:length)).to all(eq 5)
  end

  specify('scanner token count') do
    re = /^(one|two){2,3}([^d\]efm-qz\,\-]*)(ghi)+$/i
    expect(RS.scan(re).length).to eq 28
  end
end
