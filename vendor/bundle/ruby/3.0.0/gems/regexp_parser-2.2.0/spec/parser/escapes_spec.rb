require 'spec_helper'

RSpec.describe('EscapeSequence parsing') do
  include_examples 'parse', /a\ac/,          1 => [:escape, :bell,              EscapeSequence::Bell]
  include_examples 'parse', /a\ec/,          1 => [:escape, :escape,            EscapeSequence::AsciiEscape]
  include_examples 'parse', /a\fc/,          1 => [:escape, :form_feed,         EscapeSequence::FormFeed]
  include_examples 'parse', /a\nc/,          1 => [:escape, :newline,           EscapeSequence::Newline]
  include_examples 'parse', /a\rc/,          1 => [:escape, :carriage,          EscapeSequence::Return]
  include_examples 'parse', /a\tc/,          1 => [:escape, :tab,               EscapeSequence::Tab]
  include_examples 'parse', /a\vc/,          1 => [:escape, :vertical_tab,      EscapeSequence::VerticalTab]

  # meta character escapes
  include_examples 'parse', /a\.c/,          1 => [:escape, :dot,               EscapeSequence::Literal]
  include_examples 'parse', /a\?c/,          1 => [:escape, :zero_or_one,       EscapeSequence::Literal]
  include_examples 'parse', /a\*c/,          1 => [:escape, :zero_or_more,      EscapeSequence::Literal]
  include_examples 'parse', /a\+c/,          1 => [:escape, :one_or_more,       EscapeSequence::Literal]
  include_examples 'parse', /a\|c/,          1 => [:escape, :alternation,       EscapeSequence::Literal]
  include_examples 'parse', /a\(c/,          1 => [:escape, :group_open,        EscapeSequence::Literal]
  include_examples 'parse', /a\)c/,          1 => [:escape, :group_close,       EscapeSequence::Literal]
  include_examples 'parse', /a\{c/,          1 => [:escape, :interval_open,     EscapeSequence::Literal]
  include_examples 'parse', /a\}c/,          1 => [:escape, :interval_close,    EscapeSequence::Literal]

  # unicode escapes
  include_examples 'parse', /a\u0640/,       1 => [:escape, :codepoint,         EscapeSequence::Codepoint]
  include_examples 'parse', /a\u{41 1F60D}/, 1 => [:escape, :codepoint_list,    EscapeSequence::CodepointList]
  include_examples 'parse', /a\u{10FFFF}/,   1 => [:escape, :codepoint_list,    EscapeSequence::CodepointList]

  # hex escapes
  include_examples 'parse', /a\xFF/n,        1 => [:escape, :hex,               EscapeSequence::Hex]

  # octal escapes
  include_examples 'parse', /a\177/n,        1 => [:escape, :octal,             EscapeSequence::Octal]

  specify('parse chars and codepoints') do
    root = RP.parse(/\n\?\101\x42\u0043\u{44 45}/)

    expect(root[0].char).to eq "\n"
    expect(root[0].codepoint).to eq 10

    expect(root[1].char).to eq '?'
    expect(root[1].codepoint).to eq 63

    expect(root[2].char).to eq 'A'
    expect(root[2].codepoint).to eq 65

    expect(root[3].char).to eq 'B'
    expect(root[3].codepoint).to eq 66

    expect(root[4].char).to eq 'C'
    expect(root[4].codepoint).to eq 67

    expect(root[5].chars).to eq %w[D E]
    expect(root[5].codepoints).to eq [68, 69]

    expect { root[5].char }.to raise_error(/#chars/)
    expect { root[5].codepoint }.to raise_error(/#codepoints/)
  end

  # Meta/control espaces
  #
  # After the following fix in Ruby 3.1, a Regexp#source containing meta/control
  # escapes can only be set with the Regexp::new constructor.
  # In Regexp literals, these escapes are now pre-processed to hex escapes.
  #
  # https://github.com/ruby/ruby/commit/11ae581a4a7f5d5f5ec6378872eab8f25381b1b9
  def parse_meta_control(regexp_body)
    regexp = Regexp.new(regexp_body.force_encoding('ascii-8bit'), 'n')
    RP.parse(regexp)
  end

  specify('parse escape control sequence lower') do
    root = parse_meta_control('a\\\\\c2b')

    expect(root[2]).to be_instance_of(EscapeSequence::Control)
    expect(root[2].text).to eq '\\c2'
    expect(root[2].char).to eq "\x12"
    expect(root[2].codepoint).to eq 18
  end

  specify('parse escape control sequence upper') do
    root = parse_meta_control('\d\C-C\w')

    expect(root[1]).to be_instance_of(EscapeSequence::Control)
    expect(root[1].text).to eq '\\C-C'
    expect(root[1].char).to eq "\x03"
    expect(root[1].codepoint).to eq 3
  end

  specify('parse escape meta sequence') do
    root = parse_meta_control('\Z\M-Z')

    expect(root[1]).to be_instance_of(EscapeSequence::Meta)
    expect(root[1].text).to eq '\\M-Z'
    expect(root[1].char).to eq "\u00DA"
    expect(root[1].codepoint).to eq 218
  end

  specify('parse escape meta control sequence') do
    root = parse_meta_control('\A\M-\C-X')

    expect(root[1]).to be_instance_of(EscapeSequence::MetaControl)
    expect(root[1].text).to eq '\\M-\\C-X'
    expect(root[1].char).to eq "\u0098"
    expect(root[1].codepoint).to eq 152
  end

  specify('parse lower c meta control sequence') do
    root = parse_meta_control('\A\M-\cX')

    expect(root[1]).to be_instance_of(EscapeSequence::MetaControl)
    expect(root[1].text).to eq '\\M-\\cX'
    expect(root[1].char).to eq "\u0098"
    expect(root[1].codepoint).to eq 152
  end

  specify('parse escape reverse meta control sequence') do
    root = parse_meta_control('\A\C-\M-X')

    expect(root[1]).to be_instance_of(EscapeSequence::MetaControl)
    expect(root[1].text).to eq '\\C-\\M-X'
    expect(root[1].char).to eq "\u0098"
    expect(root[1].codepoint).to eq 152
  end

  specify('parse escape reverse lower c meta control sequence') do
    root = parse_meta_control('\A\c\M-X')

    expect(root[1]).to be_instance_of(EscapeSequence::MetaControl)
    expect(root[1].text).to eq '\\c\\M-X'
    expect(root[1].char).to eq "\u0098"
    expect(root[1].codepoint).to eq 152
  end
end
