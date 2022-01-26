require 'spec_helper'

RSpec.describe(Regexp::Expression::FreeSpace) do
  specify('white space quantify raises error') do
    regexp = /
      a # Comment
    /x

    root = RP.parse(regexp)
    space = root[0]

    expect(space).to be_instance_of(FreeSpace::WhiteSpace)
    expect { space.quantify(:dummy, '#') }.to raise_error(Regexp::Parser::Error)
  end

  specify('comment quantify raises error') do
    regexp = /
      a # Comment
    /x

    root = RP.parse(regexp)
    comment = root[3]

    expect(comment).to be_instance_of(FreeSpace::Comment)
    expect { comment.quantify(:dummy, '#') }.to raise_error(Regexp::Parser::Error)
  end
end
