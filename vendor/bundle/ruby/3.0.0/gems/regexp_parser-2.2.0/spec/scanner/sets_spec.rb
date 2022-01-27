require 'spec_helper'

RSpec.describe('Set scanning') do
  include_examples 'scan', /[a]/,                   0 => [:set,    :open,            '[',          0, 1]
  include_examples 'scan', /[b]/,                   2 => [:set,    :close,           ']',          2, 3]
  include_examples 'scan', /[^n]/,                  1 => [:set,    :negate,          '^',          1, 2]

  include_examples 'scan', /[c]/,                   1 => [:literal, :literal,        'c',          1, 2]
  include_examples 'scan', /[^d]/,                  2 => [:literal, :literal,        'd',          2, 3]

  include_examples 'scan', /[\b]/,                  1 => [:escape, :backspace,       '\b',         1, 3]
  include_examples 'scan', /[A\bX]/,                2 => [:escape, :backspace,       '\b',         2, 4]

  include_examples 'scan', /[\a]/,                  1 => [:escape, :bell,            '\a',         1, 3]
  include_examples 'scan', /[\e]/,                  1 => [:escape, :escape,          '\e',         1, 3]
  include_examples 'scan', /[\f]/,                  1 => [:escape, :form_feed,       '\f',         1, 3]
  include_examples 'scan', /[\n]/,                  1 => [:escape, :newline,         '\n',         1, 3]
  include_examples 'scan', /[\r]/,                  1 => [:escape, :carriage,        '\r',         1, 3]
  include_examples 'scan', /[\t]/,                  1 => [:escape, :tab,             '\t',         1, 3]
  include_examples 'scan', /[\v]/,                  1 => [:escape, :vertical_tab,    '\v',         1, 3]

  include_examples 'scan', /[.]/,                   1 => [:literal, :literal,        '.',          1, 2]
  include_examples 'scan', /[?]/,                   1 => [:literal, :literal,        '?',          1, 2]
  include_examples 'scan', /[*]/,                   1 => [:literal, :literal,        '*',          1, 2]
  include_examples 'scan', /[+]/,                   1 => [:literal, :literal,        '+',          1, 2]
  include_examples 'scan', /[{]/,                   1 => [:literal, :literal,        '{',          1, 2]
  include_examples 'scan', /[}]/,                   1 => [:literal, :literal,        '}',          1, 2]
  include_examples 'scan', /[<]/,                   1 => [:literal, :literal,        '<',          1, 2]
  include_examples 'scan', /[>]/,                   1 => [:literal, :literal,        '>',          1, 2]

  include_examples 'scan', '[\\\\]',                1 => [:escape, :backslash,       '\\\\',       1, 3]
  include_examples 'scan', '[\u0040]',              1 => [:escape, :codepoint,       '\u0040',     1, 7]
  include_examples 'scan', '[\u{40}]',              1 => [:escape, :codepoint_list,  '\u{40}',     1, 7]
  include_examples 'scan', '[\c2]',                 1 => [:escape, :control,         '\c2',        1, 4]
  include_examples 'scan', '[\C-C]',                1 => [:escape, :control,         '\C-C',       1, 5]
  include_examples 'scan', '[\x20]',                1 => [:escape, :hex,             '\x20',       1, 5]
  include_examples 'scan', '[\M-Z]',                1 => [:escape, :meta_sequence,   '\M-Z',       1, 5]
  include_examples 'scan', '[\M-\C-X]',             1 => [:escape, :meta_sequence,   '\M-\C-X',    1, 8]
  include_examples 'scan', '[\\[]',                 1 => [:escape, :set_open,        '\[',         1, 3]
  include_examples 'scan', '[\\]]',                 1 => [:escape, :set_close,       '\]',         1, 3]
  include_examples 'scan', '[a\-]',                 2 => [:escape, :literal,         '\-',         2, 4]
  include_examples 'scan', '[\-c]',                 1 => [:escape, :literal,         '\-',         1, 3]
  include_examples 'scan', '[\.]',                  1 => [:escape, :literal,         '\.',         1, 3]
  include_examples 'scan', '[\?]',                  1 => [:escape, :literal,         '\?',         1, 3]
  include_examples 'scan', '[\*]',                  1 => [:escape, :literal,         '\*',         1, 3]
  include_examples 'scan', '[\+]',                  1 => [:escape, :literal,         '\+',         1, 3]
  include_examples 'scan', '[\|]',                  1 => [:escape, :literal,         '\|',         1, 3]
  include_examples 'scan', '[\{]',                  1 => [:escape, :literal,         '\{',         1, 3]
  include_examples 'scan', '[\}]',                  1 => [:escape, :literal,         '\}',         1, 3]
  include_examples 'scan', '[\(]',                  1 => [:escape, :literal,         '\(',         1, 3]
  include_examples 'scan', '[\)]',                  1 => [:escape, :literal,         '\)',         1, 3]
  include_examples 'scan', '[\!]',                  1 => [:escape, :literal,         '\!',         1, 3]
  include_examples 'scan', '[\#]',                  1 => [:escape, :literal,         '\#',         1, 3]
  include_examples 'scan', '[\A]',                  1 => [:escape, :literal,         '\A',         1, 3]
  include_examples 'scan', '[\z]',                  1 => [:escape, :literal,         '\z',         1, 3]
  include_examples 'scan', '[\g]',                  1 => [:escape, :literal,         '\g',         1, 3]
  include_examples 'scan', '[\K]',                  1 => [:escape, :literal,         '\K',         1, 3]
  include_examples 'scan', '[\R]',                  1 => [:escape, :literal,         '\R',         1, 3]
  include_examples 'scan', '[\X]',                  1 => [:escape, :literal,         '\X',         1, 3]
  include_examples 'scan', '[\B]',                  1 => [:escape, :literal,         '\B',         1, 3]

  include_examples 'scan', /[\d]/,                  1 => [:type,   :digit,           '\d',         1, 3]
  include_examples 'scan', /[\da-z]/,               1 => [:type,   :digit,           '\d',         1, 3]
  include_examples 'scan', /[\D]/,                  1 => [:type,   :nondigit,        '\D',         1, 3]

  include_examples 'scan', /[\h]/,                  1 => [:type,   :hex,             '\h',         1, 3]
  include_examples 'scan', /[\H]/,                  1 => [:type,   :nonhex,          '\H',         1, 3]

  include_examples 'scan', /[\s]/,                  1 => [:type,   :space,           '\s',         1, 3]
  include_examples 'scan', /[\S]/,                  1 => [:type,   :nonspace,        '\S',         1, 3]

  include_examples 'scan', /[\w]/,                  1 => [:type,   :word,            '\w',         1, 3]
  include_examples 'scan', /[\W]/,                  1 => [:type,   :nonword,         '\W',         1, 3]

  include_examples 'scan', /[a-b]/,                 1 => [:literal, :literal,        'a',          1, 2]
  include_examples 'scan', /[a-c]/,                 2 => [:set,     :range,          '-',          2, 3]
  include_examples 'scan', /[a-d]/,                 3 => [:literal, :literal,        'd',          3, 4]
  include_examples 'scan', /[a-b-]/,                4 => [:literal, :literal,        '-',          4, 5]
  include_examples 'scan', /[-a]/,                  1 => [:literal, :literal,        '-',          1, 2]
  include_examples 'scan', /[a-c^]/,                4 => [:literal, :literal,        '^',          4, 5]
  include_examples 'scan', /[a-bd-f]/,              2 => [:set,     :range,          '-',          2, 3]
  include_examples 'scan', /[a-cd-f]/,              5 => [:set,     :range,          '-',          5, 6]
  # this is a buggy range, it matches only `c`, but not `a`, `b` or `-`
  include_examples 'scan', /[a-[c]]/,               2 => [:set,     :range,          '-',          2, 3]
  # these are not ranges, they match `a`, `c` and `-` (or non-`-` if negated)
  include_examples 'scan', /[[a]-[c]]/,             4 => [:literal, :literal,        '-',          4, 5]
  include_examples 'scan', /[[a]-c]/,               4 => [:literal, :literal,        '-',          4, 5]
  include_examples 'scan', /[^-c]/,                 2 => [:literal, :literal,        '-',          2, 3]

  include_examples 'scan', /[a[:digit:]c]/,         2 => [:posixclass,    :digit,    '[:digit:]',  2, 11]
  include_examples 'scan', /[[:digit:][:space:]]/,  2 => [:posixclass,    :space,    '[:space:]', 10, 19]
  include_examples 'scan', /[[:^digit:]]/,          1 => [:nonposixclass, :digit,    '[:^digit:]', 1, 11]

  include_examples 'scan', /[a-d&&g-h]/,            4 => [:set,    :intersection,    '&&',         4, 6]
  include_examples 'scan', /[a&&]/,                 2 => [:set,    :intersection,    '&&',         2, 4]
  include_examples 'scan', /[&&z]/,                 1 => [:set,    :intersection,    '&&',         1, 3]
  include_examples 'scan', /[&&]/,                  1 => [:set,    :intersection,    '&&',         1, 3]

  include_examples 'scan', '[a\p{digit}c]',         2 => [:property,    :digit,      '\p{digit}',  2, 11]
  include_examples 'scan', '[a\P{digit}c]',         2 => [:nonproperty, :digit,      '\P{digit}',  2, 11]
  include_examples 'scan', '[a\p{^digit}c]',        2 => [:nonproperty, :digit,      '\p{^digit}', 2, 12]
  include_examples 'scan', '[a\P{^digit}c]',        2 => [:property,    :digit,      '\P{^digit}', 2, 12]

  include_examples 'scan', '[a\p{ALPHA}c]',         2 => [:property,    :alpha,      '\p{ALPHA}',  2, 11]
  include_examples 'scan', '[a\p{P}c]',             2 => [:property,    :punctuation,'\p{P}',      2, 7]
  include_examples 'scan', '[a\p{P}\P{P}c]',        3 => [:nonproperty, :punctuation,'\P{P}',      7, 12]

  include_examples 'scan', '[\x20-\x27]',
    1 => [:escape, :hex,             '\x20',       1, 5],
    2 => [:set,    :range,           '-',          5, 6],
    3 => [:escape, :hex,             '\x27',       6, 10]

  include_examples 'scan', '[a-w&&[^c-g]z]',
    5 => [:set,    :open,            '[',          6, 7],
    6 => [:set,    :negate,          '^',          7, 8],
    8 => [:set,    :range,           '-',          9, 10],
    10=> [:set,    :close,           ']',          11, 12]

  # Collations/collating sequences and character equivalents are not enabled
  # in Ruby at the moment. If they ever are, enable them in the scanner,
  # add them to a new syntax version, and handle them in the parser. Until then,
  # expect them to be scanned as regular subsets containing literals.
  # include_examples 'scan', /[a[.a-b.]c]/,           2 => [:set,    :collation,       '[.a-b.]',    2,  9]
  # include_examples 'scan', /[a[=e=]c]/,             2 => [:set,    :equivalent,      '[=e=]',      2,  7]
  include_examples 'scan', '[a[.a-b.]c]',
    2 => [:set,     :open,           '[',          2,  3],
    3 => [:literal, :literal,        '.',          3,  4],
    4 => [:literal, :literal,        'a',          4,  5]
  include_examples 'scan', '[a[=e=]c]',
    2 => [:set,     :open,           '[',          2,  3],
    3 => [:literal, :literal,        '=',          3,  4],
    4 => [:literal, :literal,        'e',          4,  5]

  # multi-byte characters should not affect indices
  include_examples 'scan', /[れます]/,
    0 => [:set,     :open,           '[',          0, 1],
    1 => [:literal, :literal,        'れ',          1, 2],
    2 => [:literal, :literal,        'ま',          2, 3],
    3 => [:literal, :literal,        'す',          3, 4],
    4 => [:set,     :close,          ']',          4, 5]

  specify('set literal encoding') do
    text = RS.scan('[a]')[1][2].to_s
    expect(text).to eq 'a'
    expect(text.encoding.to_s).to eq 'UTF-8'

    text = RS.scan("[\u{1F632}]")[1][2].to_s
    expect(text).to eq "\u{1F632}"
    expect(text.encoding.to_s).to eq 'UTF-8'
  end
end
