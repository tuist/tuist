require 'cucumber/cucumber_expressions/tree_regexp'

module Cucumber
  module CucumberExpressions
    describe TreeRegexp do
      it 'exposes group source' do
        tr = TreeRegexp.new(/(a(?:b)?)(c)/)
        expect(tr.group_builder.children.map{|gb| gb.source}).to eq(['a(?:b)?', 'c'])
      end

      it 'builds tree' do
        tr = TreeRegexp.new(/(a(?:b)?)(c)/)
        group = tr.match('ac')
        expect(group.value).to eq('ac')
        expect(group.children[0].value).to eq('a')
        expect(group.children[0].children).to eq([])
        expect(group.children[1].value).to eq('c')
      end

      it 'ignores `?:` as a non-capturing group' do
        tr = TreeRegexp.new(/a(?:b)(c)/)
        group = tr.match('abc')
        expect(group.value).to eq('abc')
        expect(group.children.length).to eq 1
        expect(group.children[0].value).to eq('c')
      end

      it 'ignores `?!` as a non-capturing group' do
        tr = TreeRegexp.new(/a(?!b)(.+)/)
        group = tr.match('aBc')
        expect(group.value).to eq('aBc')
        expect(group.children.length).to eq 1
      end

      it 'ignores `?=` as a non-capturing group' do
        tr = TreeRegexp.new(/a(?=b)(.+)$/)
        group = tr.match('abc')
        expect(group.value).to eq('abc')
        expect(group.children[0].value).to eq('bc')
        expect(group.children.length).to eq 1
      end

      it 'ignores `?<=` as a non-capturing group' do
        tr = TreeRegexp.new(/a(.+)(?<=c)$/)
        group = tr.match('abc')
        expect(group.value).to eq('abc')
        expect(group.children[0].value).to eq('bc')
        expect(group.children.length).to eq 1
      end

      it 'ignores `?<!` as a non-capturing group' do
        tr = TreeRegexp.new(/a(.+)(?<!b)$/)
        group = tr.match('abc')
        expect(group.value).to eq('abc')
        expect(group.children[0].value).to eq('bc')
        expect(group.children.length).to eq 1
      end

      it 'ignores `?<!` as a non-capturing group' do
        tr = TreeRegexp.new(/a(.+)(?<!b)$/)
        group = tr.match('abc')
        expect(group.value).to eq('abc')
        expect(group.children[0].value).to eq('bc')
        expect(group.children.length).to eq 1
      end

      it 'ignores `?>` as a non-capturing group' do
        tr = TreeRegexp.new(/a(?>b)c/)
        group = tr.match('abc')
        expect(group.value).to eq('abc')
        expect(group.children.length).to eq 0
      end

      it 'throws an error when there are named capture groups because they are buggy in Ruby' do
        # https://github.com/cucumber/cucumber/issues/329
        expect {
          TreeRegexp.new(/^I am a person( named "(?<first_name>.+) (?<last_name>.+)")?$/)
        }.to raise_error(/Named capture groups are not supported/)
      end

      it 'matches optional group' do
        tr = TreeRegexp.new(/^Something( with an optional argument)?/)
        group = tr.match('Something')
        expect(group.children[0].value).to eq(nil)
      end

      it 'matches nested groups' do
        tr = TreeRegexp.new(/^A (\d+) thick line from ((\d+),\s*(\d+),\s*(\d+)) to ((\d+),\s*(\d+),\s*(\d+))/)
        group = tr.match('A 5 thick line from 10,20,30 to 40,50,60')

        expect(group.children[0].value).to eq('5')
        expect(group.children[1].value).to eq('10,20,30')
        expect(group.children[1].children[0].value).to eq('10')
        expect(group.children[1].children[1].value).to eq('20')
        expect(group.children[1].children[2].value).to eq('30')
        expect(group.children[2].value).to eq('40,50,60')
        expect(group.children[2].children[0].value).to eq('40')
        expect(group.children[2].children[1].value).to eq('50')
        expect(group.children[2].children[2].value).to eq('60')
      end

      it 'detects multiple non capturing groups' do
        tr = TreeRegexp.new(/(?:a)(:b)(\?c)(d)/)
        group = tr.match("a:b?cd")
        expect(group.children.length).to eq(3)
      end

      it 'works with escaped backslash' do
        tr = TreeRegexp.new(/foo\\(bar|baz)/)
        group = tr.match("foo\\bar")
        expect(group.children.length).to eq(1)
      end

      it 'works with escaped slash' do
        tr = TreeRegexp.new(/^I go to '\/(.+)'$/)
        group = tr.match("I go to '/hello'")
        expect(group.children.length).to eq(1)
      end

      it 'works with digit and word' do
        tr = TreeRegexp.new(/^(\d) (\w+)$/)
        group = tr.match("2 you")
        expect(group.children.length).to eq(2)
      end

      it 'captures non capturing groups with capturing groups inside' do
        tr = TreeRegexp.new(/the stdout(?: from "(.*?)")?/)
        group = tr.match("the stdout")
        expect(group.value).to eq("the stdout")
        expect(group.children[0].value).to eq(nil)
        expect(group.children.length).to eq(1)
      end

      it 'works with flags' do
        tr = TreeRegexp.new(/HELLO/i)
        group = tr.match("hello")
        expect(group.value).to eq("hello")
      end

      it('does not consider parenthesis in character class as group') do
        tr = TreeRegexp.new(/^drawings: ([A-Z_, ()]+)$/)
        group = tr.match('drawings: ONE, TWO(ABC)')
        expect(group.value).to eq('drawings: ONE, TWO(ABC)')
        expect(group.children[0].value).to eq('ONE, TWO(ABC)')
        expect(group.children.length).to eq(1)
      end

      it 'works with inline flags' do
        tr = TreeRegexp.new(/(?i)HELLO/)
        group = tr.match('hello')
        expect(group.value).to eq('hello')
        expect(group.children.length).to eq 0
      end

      it 'works with non capturing inline flags' do
        tr = TreeRegexp.new(/(?i:HELLO)/)
        group = tr.match('hello')
        expect(group.value).to eq('hello')
        expect(group.children.length).to eq 0
      end

      it 'works with empty capturing group' do
        tr = TreeRegexp.new(/()/)
        group = tr.match('')
        expect(group.value).to eq('')
        expect(group.children[0].value).to eq('')
        expect(group.children.length).to eq 1
      end

      it 'works with empty non-capturing group' do
        tr = TreeRegexp.new(/(?:)/)
        group = tr.match('')
        expect(group.value).to eq('')
        expect(group.children.length).to eq 0
      end

      it 'works with empty non-look ahead' do
        tr = TreeRegexp.new(/(?<=)/)
        group = tr.match('')
        expect(group.value).to eq('')
        expect(group.children.length).to eq 0
      end

    end
  end
end
