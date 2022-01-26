require 'spec_helper'

RSpec.describe('CharacterType parsing') do
  include_examples 'parse', /a\dc/,   1 =>  [:type,   :digit,     CharacterType::Digit]
  include_examples 'parse', /a\Dc/,   1 =>  [:type,   :nondigit,  CharacterType::NonDigit]

  include_examples 'parse', /a\sc/,   1 =>  [:type,   :space,     CharacterType::Space]
  include_examples 'parse', /a\Sc/,   1 =>  [:type,   :nonspace,  CharacterType::NonSpace]

  include_examples 'parse', /a\hc/,   1 =>  [:type,   :hex,       CharacterType::Hex]
  include_examples 'parse', /a\Hc/,   1 =>  [:type,   :nonhex,    CharacterType::NonHex]

  include_examples 'parse', /a\wc/,   1 =>  [:type,   :word,      CharacterType::Word]
  include_examples 'parse', /a\Wc/,   1 =>  [:type,   :nonword,   CharacterType::NonWord]

  include_examples 'parse', 'a\\Rc',  1 =>  [:type,   :linebreak, CharacterType::Linebreak]
  include_examples 'parse', 'a\\Xc',  1 =>  [:type,   :xgrapheme, CharacterType::ExtendedGrapheme]
end
