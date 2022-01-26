require 'cucumber/html_formatter/template_writer'

describe Cucumber::HTMLFormatter::TemplateWriter do
  context 'write_between' do
    let(:subject) { writer = Cucumber::HTMLFormatter::TemplateWriter.new(template) }
    let(:template) { 'Some template {{here}} with content after' }

    it 'outputs content of the template between the given words' do
      expect(subject.write_between('Some', 'content')).to eq(' template {{here}} with ')
    end

    context 'when "from" argument is nil' do
      it 'outputs template from the beginning' do
        expect(subject.write_between(nil, '{{here}}')).to eq('Some template ')
      end
    end

    context 'when "to" argument is nil' do
      it 'outputs content of template after the "from" argument value' do
        expect(subject.write_between('{{here}}', nil)).to eq(' with content after')
      end
    end

    context 'when "from" argument is missing from the template' do
      it 'renders the template from the beginning' do
        expect(subject.write_between('Unknown start', '{{here}}')).to eq('Some template ')
      end
    end
  end
end