RSpec.shared_examples 'syntax' do |klass, opts|
  opts[:implements].each do |type, tokens|
    tokens.each do |token|
      it("implements #{token} #{type}") do
        expect(klass.implements?(type, token)).to be true
      end
    end
  end

  opts[:excludes] && opts[:excludes].each do |type, tokens|
    tokens.each do |token|
      it("does not implement #{token} #{type}") do
        expect(klass.implements?(type, token)).to be false
      end
    end
  end
end

RSpec.shared_examples 'scan' do |pattern, checks|
  context "given the pattern #{pattern}" do
    before(:all) { @tokens = Regexp::Scanner.scan(pattern) }

    checks.each do |index, (type, token, text, ts, te)|
      it "scans token #{index} as #{token} #{type} at #{ts}..#{te}" do
        result = @tokens.at(index)

        expect(result[0]).to eq type
        expect(result[1]).to eq token
        expect(result[2]).to eq text
        expect(result[3]).to eq ts
        expect(result[4]).to eq te
      end
    end
  end
end

RSpec.shared_examples 'lex' do |pattern, checks|
  context "given the pattern #{pattern}" do
    before(:all) { @tokens = Regexp::Lexer.lex(pattern) }

    checks.each do |index, (type, token, text, ts, te, lvl, set_lvl, cond_lvl)|
      it "lexes token #{index} as #{token} #{type} at #{lvl}, #{set_lvl}, #{cond_lvl}" do
        struct = @tokens.at(index)

        expect(struct.type).to eq type
        expect(struct.token).to eq token
        expect(struct.text).to eq text
        expect(struct.ts).to eq ts
        expect(struct.te).to eq te
        expect(struct.level).to eq lvl
        expect(struct.set_level).to eq set_lvl
        expect(struct.conditional_level).to eq cond_lvl
      end
    end
  end
end

RSpec.shared_examples 'parse' do |pattern, checks|
  context "given the pattern #{pattern}" do
    before(:all) { @root = Regexp::Parser.parse(pattern, '*') }

    checks.each do |path, (type, token, klass, attributes)|
      it "parses expression at #{path} as #{klass}" do
        exp = @root.dig(*path)

        expect(exp).to be_instance_of(klass)
        expect(exp.type).to eq type
        expect(exp.token).to eq token

        attributes && attributes.each do |method, value|
          expect(exp.send(method)).to eq(value),
            "expected expression at #{path} to have #{method} #{value}"
        end
      end
    end
  end
end
