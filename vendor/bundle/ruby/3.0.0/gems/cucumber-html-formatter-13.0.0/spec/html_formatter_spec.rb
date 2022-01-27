require 'cucumber/messages'
require 'cucumber/html_formatter'

class FakeAssets
  def template
    "<html>{{css}}<body>{{messages}}</body>{{script}}</html>"
  end

  def css
    "<style>div { color: red }</style>"
  end

  def script
    "<script>alert('Hi')</script>"
  end
end

describe Cucumber::HTMLFormatter::Formatter do
  let(:subject) {
    formatter = Cucumber::HTMLFormatter::Formatter.new(out)
    allow(formatter).to receive(:assets_loader).and_return(assets)
    formatter
  }
  let(:out) { StringIO.new }
  let(:assets) { FakeAssets.new }

  context '.write_pre_message' do
    it 'outputs the content of the template up to {{messages}}' do
      subject.write_pre_message()
      expect(out.string).to eq("<html>\n<style>div { color: red }</style>\n<body>\n")
    end

    it 'does not write the content twice' do
      subject.write_pre_message()
      subject.write_pre_message()

      expect(out.string).to eq("<html>\n<style>div { color: red }</style>\n<body>\n")
    end
  end

  context '.write_message' do
    let(:message) do
      Cucumber::Messages::Envelope.new({
        pickle: Cucumber::Messages::Pickle.new({
          id: 'some-random-uid'
        })
      })
    end

    it 'raises an exception if the message is not a Cucumber::Messages::Envelope instance' do
      expect { subject.write_message('Ho hi !') }.to raise_exception(Cucumber::HTMLFormatter::MessageExpected)
    end

    it 'appends the message to out' do
      subject.write_message(message)
      expect(out.string).to eq(%|{"pickle":{"id":"some-random-uid"}}|)
    end

    it 'adds commas between the messages' do
      subject.write_message(message)
      subject.write_message(message)

      expect(out.string).to eq(%|{"pickle":{"id":"some-random-uid"}},\n{"pickle":{"id":"some-random-uid"}}|)
    end
  end

  context '.write_post_message' do
    it 'outputs the template end' do
      subject.write_post_message()
      expect(out.string).to eq("</body>\n<script>alert('Hi')</script>\n</html>")
    end
  end

  context '.process_messages' do
    let(:message) do
      Cucumber::Messages::Envelope.new({
        pickle: Cucumber::Messages::Pickle.new({
          id: 'some-random-uid'
        })
      })
    end

    it 'produces the full html report' do
      subject.process_messages([message])
      expect(out.string).to eq([
        '<html>',
        '<style>div { color: red }</style>',
        '<body>',
        '{"pickle":{"id":"some-random-uid"}}</body>',
        "<script>alert('Hi')</script>",
        '</html>'
      ].join("\n"))
    end
  end
end
