require 'spec_helper'

RSpec.describe('PosixClass parsing') do
  include_examples 'parse', /[[:word:]]/,  [0, 0] => [:posixclass,    :word, PosixClass,
                                           name: 'word', text: '[:word:]', negative?: false]
  include_examples 'parse', /[[:^word:]]/, [0, 0] => [:nonposixclass, :word, PosixClass,
                                           name: 'word', text: '[:^word:]', negative?: true]
end
