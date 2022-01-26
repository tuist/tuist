require 'spec_helper'

RSpec.describe('RefCall lexing') do
  # Traditional numerical group back-reference
  include_examples 'lex', '(abc)\1',
    3 => [:backref, :number,                '\1',         5,  7, 0, 0, 0]

  # Group back-references, named, numbered, and relative
  include_examples 'lex', '(?<X>abc)\k<X>',
    3 => [:backref, :name_ref,              '\k<X>',      9, 14, 0, 0, 0]
  include_examples 'lex', "(?<X>abc)\\k'X'",
    3 => [:backref, :name_ref,              "\\k'X'",     9, 14, 0, 0, 0]

  include_examples 'lex', '(abc)\k<1>',
    3 => [:backref, :number_ref,            '\k<1>',      5, 10, 0, 0, 0]
  include_examples 'lex', "(abc)\\k'1'",
    3 => [:backref, :number_ref,            "\\k'1'",     5, 10, 0, 0, 0]

  include_examples 'lex', '(abc)\k<-1>',
    3 => [:backref, :number_rel_ref,        '\k<-1>',     5, 11, 0, 0, 0]
  include_examples 'lex', "(abc)\\k'-1'",
    3 => [:backref, :number_rel_ref,        "\\k'-1'",    5, 11, 0, 0, 0]

  # Sub-expression invocation, named, numbered, and relative
  include_examples 'lex', '(?<X>abc)\g<X>',
    3 => [:backref, :name_call,             '\g<X>',      9, 14, 0, 0, 0]
  include_examples 'lex', "(?<X>abc)\\g'X'",
    3 => [:backref, :name_call,             "\\g'X'",     9, 14, 0, 0, 0]

  include_examples 'lex', '(abc)\g<1>',
    3 => [:backref, :number_call,           '\g<1>',      5, 10, 0, 0, 0]
  include_examples 'lex', "(abc)\\g'1'",
    3 => [:backref, :number_call,           "\\g'1'",     5, 10, 0, 0, 0]

  include_examples 'lex', '\g<0>',
    0 => [:backref, :number_call,           '\g<0>',      0,  5, 0, 0, 0]
  include_examples 'lex', "\\g'0'",
    0 => [:backref, :number_call,           "\\g'0'",     0,  5, 0, 0, 0]

  include_examples 'lex', '(abc)\g<-1>',
    3 => [:backref, :number_rel_call,       '\g<-1>',     5, 11, 0, 0, 0]
  include_examples 'lex', "(abc)\\g'-1'",
    3 => [:backref, :number_rel_call,       "\\g'-1'",    5, 11, 0, 0, 0]

  include_examples 'lex', '(abc)\g<+1>',
    3 => [:backref, :number_rel_call,       '\g<+1>',     5, 11, 0, 0, 0]
  include_examples 'lex', "(abc)\\g'+1'",
    3 => [:backref, :number_rel_call,       "\\g'+1'",    5, 11, 0, 0, 0]

  # Group back-references, with nesting level
  include_examples 'lex', '(?<X>abc)\k<X-0>',
    3 => [:backref, :name_recursion_ref,    '\k<X-0>',    9, 16, 0, 0, 0]
  include_examples 'lex', "(?<X>abc)\\k'X-0'",
    3 => [:backref, :name_recursion_ref,    "\\k'X-0'",   9, 16, 0, 0, 0]

  include_examples 'lex', '(abc)\k<1-0>',
    3 => [:backref, :number_recursion_ref,  '\k<1-0>',    5, 12, 0, 0, 0]
  include_examples 'lex', "(abc)\\k'1-0'",
    3 => [:backref, :number_recursion_ref,  "\\k'1-0'",   5, 12, 0, 0, 0]
end
