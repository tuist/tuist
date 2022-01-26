require 'spec_helper'

RSpec.describe SimCtl::Executor do
  describe '#execute' do
    it 'raises an exception' do
      expect { SimCtl::Executor.execute(['xcrun simctl asdf']) }.to raise_error RuntimeError
    end

    it 'returns json' do
      json = SimCtl::Executor.execute(["echo '{\"foo\":\"bar\"}'"]) do |result|
        result
      end
      expect(json).to eql('foo' => 'bar')
    end

    it 'returns a string' do
      string = SimCtl::Executor.execute(["echo 'hello world'"]) do |result|
        result
      end
      expect(string).to eql('hello world')
    end
  end
end
