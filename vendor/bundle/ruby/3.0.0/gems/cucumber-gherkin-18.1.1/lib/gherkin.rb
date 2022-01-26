require_relative 'gherkin/stream/parser_message_stream'

module Gherkin
  DEFAULT_OPTIONS = {
    include_source: true,
    include_gherkin_document: true,
    include_pickles: true
  }.freeze

  def self.from_paths(paths, options={})
    Stream::ParserMessageStream.new(
        paths,
        [],
        options
    ).messages
  end

  def self.from_sources(sources, options={})
    Stream::ParserMessageStream.new(
        [],
        sources,
        options
    ).messages
  end

  def self.from_source(uri, data, options={})
    from_sources([encode_source_message(uri, data)], options)
  end

  private

  def self.encode_source_message(uri, data)
    Cucumber::Messages::Source.new({
      uri: uri,
      data: data,
      media_type: 'text/x.cucumber.gherkin+plain'
    })
  end
end
