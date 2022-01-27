# frozen_string_literal: true

require 'cucumber/formatter/io'
require 'cucumber/formatter/message_builder'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format message</tt>
    class Message < MessageBuilder
      include Io

      def initialize(config)
        @io = ensure_io(config.out_stream, config.error_stream)
        super(config)
      end

      def output_envelope(envelope)
        envelope.write_ndjson_to(@io)
      end
    end
  end
end
