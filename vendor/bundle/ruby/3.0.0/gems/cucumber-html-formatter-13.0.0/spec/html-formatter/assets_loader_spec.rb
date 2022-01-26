require 'cucumber/html_formatter/assets_loader'

describe Cucumber::HTMLFormatter::AssetsLoader do
  let(:subject) { Cucumber::HTMLFormatter::AssetsLoader.new }

  before do
    allow(File).to receive(:read).and_return('whatever content')
  end

  context '.template' do
    it 'reads the content of assets/index.mustache.html' do
      expect(subject.template).to eq('whatever content')
      expect(File).to have_received(:read).with(/.*\/assets\/index\.mustache\.html$/)
    end
  end

  context '.css' do
    it 'reads the content of assets/cucumber-react.css' do
      expect(subject.css).to eq('whatever content')
      expect(File).to have_received(:read).with(/.*\/assets\/cucumber-react\.css$/)
    end
  end

  context '.script' do
    it 'reads the content of assets/cucumber-html\.js' do
      expect(subject.script).to eq('whatever content')
      expect(File).to have_received(:read).with(/.*\/assets\/cucumber-html\.js$/)
    end
  end
end