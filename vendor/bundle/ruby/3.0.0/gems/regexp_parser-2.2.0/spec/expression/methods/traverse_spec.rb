require 'spec_helper'

RSpec.describe('Subexpression#traverse') do
  specify('Subexpression#traverse') do
    root = RP.parse(/a(b(c(d)))|g[h-i]j|klmn/)

    enters = 0
    visits = 0
    exits = 0

    root.traverse do |event, _exp, _index|
      enters = (enters + 1) if event == :enter
      visits = (visits + 1) if event == :visit
      exits = (exits + 1) if event == :exit
    end

    expect(enters).to eq 9
    expect(enters).to eq exits

    expect(visits).to eq 9
  end

  specify('Subexpression#traverse including self') do
    root = RP.parse(/a(b(c(d)))|g[h-i]j|klmn/)

    enters = 0
    visits = 0
    exits = 0

    root.traverse(true) do |event, _exp, _index|
      enters = (enters + 1) if event == :enter
      visits = (visits + 1) if event == :visit
      exits = (exits + 1) if event == :exit
    end

    expect(enters).to eq 10
    expect(enters).to eq exits

    expect(visits).to eq 9
  end

  specify('Subexpression#traverse without a block') do
    root = RP.parse(/abc/)
    enum = root.traverse

    expect(enum).to be_a(Enumerator)
    event, expr, idx = enum.next
    expect(event).to eq(:visit)
    expect(expr).to be_a(Regexp::Expression::Literal)
    expect(idx).to eq(0)
  end

  specify('Subexpression#walk alias') do
    root = RP.parse(/abc/)

    expect(root).to respond_to(:walk)
  end

  specify('Subexpression#each_expression') do
    root = RP.parse(/a(?x:b(c))|g[h-k]/)

    count = 0
    root.each_expression { count += 1 }

    expect(count).to eq 13
  end

  specify('Subexpression#each_expression including self') do
    root = RP.parse(/a(?x:b(c))|g[h-k]/)

    count = 0
    root.each_expression(true) { count += 1 }

    expect(count).to eq 14
  end

  specify('Subexpression#each_expression indices') do
    root = RP.parse(/a(b)c/)

    indices = []
    root.each_expression { |_exp, index| (indices << index) }

    expect(indices).to eq [0, 1, 0, 2]
  end

  specify('Subexpression#each_expression indices including self') do
    root = RP.parse(/a(b)c/)

    indices = []
    root.each_expression(true) { |_exp, index| (indices << index) }

    expect(indices).to eq [0, 0, 1, 0, 2]
  end

  specify('Subexpression#each_expression without a block') do
    root = RP.parse(/abc/)
    enum = root.each_expression

    expect(enum).to be_a(Enumerator)
    expr, idx = enum.next
    expect(expr).to be_a(Regexp::Expression::Literal)
    expect(idx).to eq(0)
  end

  specify('Subexpression#flat_map without block') do
    root = RP.parse(/a(b([c-e]+))?/)

    array = root.flat_map

    expect(array).to be_instance_of(Array)
    expect(array.length).to eq 8

    array.each do |item|
      expect(item).to be_instance_of(Array)
      expect(item.length).to eq 2
      expect(item.first).to be_a(Regexp::Expression::Base)
      expect(item.last).to be_a(Integer)
    end
  end

  specify('Subexpression#flat_map without block including self') do
    root = RP.parse(/a(b([c-e]+))?/)

    array = root.flat_map(true)

    expect(array).to be_instance_of(Array)
    expect(array.length).to eq 9
  end

  specify('Subexpression#flat_map indices') do
    root = RP.parse(/a(b([c-e]+))?f*g/)

    indices = root.flat_map { |_exp, index| index }

    expect(indices).to eq [0, 1, 0, 1, 0, 0, 0, 1, 2, 3]
  end

  specify('Subexpression#flat_map indices including self') do
    root = RP.parse(/a(b([c-e]+))?f*g/)

    indices = root.flat_map(true) { |_exp, index| index }

    expect(indices).to eq [0, 0, 1, 0, 1, 0, 0, 0, 1, 2, 3]
  end

  specify('Subexpression#flat_map expressions') do
    root = RP.parse(/a(b(c(d)))/)

    levels = root.flat_map { |exp, _index| [exp.level, exp.text] if exp.terminal? }.compact

    expect(levels).to eq [[0, 'a'], [1, 'b'], [2, 'c'], [3, 'd']]
  end

  specify('Subexpression#flat_map expressions including self') do
    root = RP.parse(/a(b(c(d)))/)

    levels = root.flat_map(true) { |exp, _index| [exp.level, exp.to_s] }.compact

    expect(levels).to eq [[nil, 'a(b(c(d)))'], [0, 'a'], [0, '(b(c(d)))'], [1, 'b'], [1, '(c(d))'], [2, 'c'], [2, '(d)'], [3, 'd']]
  end
end
