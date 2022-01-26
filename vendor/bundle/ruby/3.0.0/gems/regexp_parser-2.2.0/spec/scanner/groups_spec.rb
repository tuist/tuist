require 'spec_helper'

RSpec.describe('Group scanning') do
  # Group types
  include_examples 'scan', '(?>abc)',         0 => [:group,     :atomic,         '(?>',        0, 3]
  include_examples 'scan', '(abc)',           0 => [:group,     :capture,        '(',          0, 1]

  # Named groups
  # only names that start with a hyphen or digit (ascii or other) are invalid
  include_examples 'scan', '(?<name>abc)',    0 => [:group,     :named_ab,       '(?<name>',   0, 8]
  include_examples 'scan', "(?'name'abc)",    0 => [:group,     :named_sq,       "(?'name'",   0, 8]
  include_examples 'scan', '(?<name_1>abc)',  0 => [:group,     :named_ab,       '(?<name_1>', 0,10]
  include_examples 'scan', "(?'name_1'abc)",  0 => [:group,     :named_sq,       "(?'name_1'", 0,10]
  include_examples 'scan', '(?<name-1>abc)',  0 => [:group,     :named_ab,       '(?<name-1>', 0,10]
  include_examples 'scan', "(?'name-1'abc)",  0 => [:group,     :named_sq,       "(?'name-1'", 0,10]
  include_examples 'scan', "(?<name'1>abc)",  0 => [:group,     :named_ab,       "(?<name'1>", 0,10]
  include_examples 'scan', "(?'name>1'abc)",  0 => [:group,     :named_sq,       "(?'name>1'", 0,10]
  include_examples 'scan', '(?<üüuuüü>abc)',  0 => [:group,     :named_ab,       '(?<üüuuüü>', 0,10]
  include_examples 'scan', "(?'üüuuüü'abc)",  0 => [:group,     :named_sq,       "(?'üüuuüü'", 0,10]
  include_examples 'scan', "(?<😋1234😋>abc)",  0 => [:group,     :named_ab,       "(?<😋1234😋>", 0,10]
  include_examples 'scan', "(?'😋1234😋'abc)",  0 => [:group,     :named_sq,       "(?'😋1234😋'", 0,10]

  include_examples 'scan', '(?:abc)',         0 => [:group,     :passive,        '(?:',        0, 3]
  include_examples 'scan', '(?:)',            0 => [:group,     :passive,        '(?:',        0, 3]
  include_examples 'scan', '(?::)',           0 => [:group,     :passive,        '(?:',        0, 3]

  # Comments
  include_examples 'scan', '(?#abc)',         0 => [:group,     :comment,        '(?#abc)',    0, 7]
  include_examples 'scan', '(?#)',            0 => [:group,     :comment,        '(?#)',       0, 4]

  # Assertions
  include_examples 'scan', '(?=abc)',         0 => [:assertion, :lookahead,      '(?=',        0, 3]
  include_examples 'scan', '(?!abc)',         0 => [:assertion, :nlookahead,     '(?!',        0, 3]
  include_examples 'scan', '(?<=abc)',        0 => [:assertion, :lookbehind,     '(?<=',       0, 4]
  include_examples 'scan', '(?<!abc)',        0 => [:assertion, :nlookbehind,    '(?<!',       0, 4]

  # Options
  include_examples 'scan', '(?-mix:abc)',     0 => [:group,     :options,        '(?-mix:',    0, 7]
  include_examples 'scan', '(?m-ix:abc)',     0 => [:group,     :options,        '(?m-ix:',    0, 7]
  include_examples 'scan', '(?mi-x:abc)',     0 => [:group,     :options,        '(?mi-x:',    0, 7]
  include_examples 'scan', '(?mix:abc)',      0 => [:group,     :options,        '(?mix:',     0, 6]
  include_examples 'scan', '(?m:)',           0 => [:group,     :options,        '(?m:',       0, 4]
  include_examples 'scan', '(?i:)',           0 => [:group,     :options,        '(?i:',       0, 4]
  include_examples 'scan', '(?x:)',           0 => [:group,     :options,        '(?x:',       0, 4]
  include_examples 'scan', '(?mix)',          0 => [:group,     :options_switch, '(?mix',      0, 5]
  include_examples 'scan', '(?d-mix:abc)',    0 => [:group,     :options,        '(?d-mix:',   0, 8]
  include_examples 'scan', '(?a-mix:abc)',    0 => [:group,     :options,        '(?a-mix:',   0, 8]
  include_examples 'scan', '(?u-mix:abc)',    0 => [:group,     :options,        '(?u-mix:',   0, 8]
  include_examples 'scan', '(?da-m:abc)',     0 => [:group,     :options,        '(?da-m:',    0, 7]
  include_examples 'scan', '(?du-x:abc)',     0 => [:group,     :options,        '(?du-x:',    0, 7]
  include_examples 'scan', '(?dau-i:abc)',    0 => [:group,     :options,        '(?dau-i:',   0, 8]
  include_examples 'scan', '(?dau:abc)',      0 => [:group,     :options,        '(?dau:',     0, 6]
  include_examples 'scan', '(?d:)',           0 => [:group,     :options,        '(?d:',       0, 4]
  include_examples 'scan', '(?a:)',           0 => [:group,     :options,        '(?a:',       0, 4]
  include_examples 'scan', '(?u:)',           0 => [:group,     :options,        '(?u:',       0, 4]
  include_examples 'scan', '(?dau)',          0 => [:group,     :options_switch, '(?dau',      0, 5]

  if ruby_version_at_least('2.4.1')
    include_examples 'scan', '(?~abc)', 0 => [:group, :absence, '(?~', 0, 3]
  end
end
