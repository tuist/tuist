require 'cucumber/messages'
require 'cucumber/html_formatter/template_writer'
require 'cucumber/html_formatter/assets_loader'


module Cucumber
  module HTMLFormatter
    class MessageExpected < StandardError; end

    class Formatter
      attr_reader :out

      def initialize(out)
        @out = out
        @pre_message_written = false
        @first_message = true
      end

      def process_messages(messages)
        write_pre_message
        messages.each { |message| write_message(message) }
        write_post_message
      end

      def write_pre_message
        return if @pre_message_written

        out.puts(pre_message)
        @pre_message_written = true
      end

      def write_message(message)
        raise MessageExpected unless message.is_a?(Cucumber::Messages::Envelope)
        unless @first_message
          out.puts(',')
        end
       out.print(message.to_json(proto3: true))

        @first_message = false
      end

      def write_post_message
        out.print(post_message)
      end

      private

      def assets_loader
        @assets_loader ||= AssetsLoader.new
      end

      def pre_message
        [
          template_writer.write_between(nil, '{{css}}'),
          assets_loader.css,
          template_writer.write_between('{{css}}', '{{messages}}')
        ].join("\n")
      end

      def post_message
        [
          template_writer.write_between('{{messages}}', '{{script}}'),
          assets_loader.script,
          template_writer.write_between('{{script}}', nil)
        ].join("\n")
      end

      def template_writer
        @template_writer ||= TemplateWriter.new(assets_loader.template)
      end
    end
  end
end