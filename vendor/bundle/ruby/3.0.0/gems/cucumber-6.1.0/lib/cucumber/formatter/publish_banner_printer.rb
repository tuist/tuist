# frozen_string_literal: true

require 'cucumber/term/banner'

module Cucumber
  module Formatter
    class PublishBannerPrinter
      include Term::Banner

      def initialize(configuration)
        return if configuration.publish_enabled?

        configuration.on_event :test_run_finished do |_event|
          display_publish_ad(configuration.error_stream)
        end
      end

      # rubocop:disable Metrics/MethodLength
      def display_publish_ad(io)
        display_banner(
          [
            [
              'Share your Cucumber Report with your team at ',
              link('https://reports.cucumber.io')
            ],
            '',
            [
              'Command line option:    ',
              highlight('--publish')
            ],
            [
              'Environment variable:   ',
              highlight('CUCUMBER_PUBLISH_ENABLED'),
              '=',
              highlight('true')
            ],
            [
              'cucumber.yml:           ',
              highlight('default: --publish')
            ],
            '',
            [
              'More information at ',
              link('https://reports.cucumber.io/docs/cucumber-ruby')
            ],
            '',
            [
              'To disable this message, specify ',
              pre('CUCUMBER_PUBLISH_QUIET=true'),
              ' or use the '
            ],
            [
              pre('--publish-quiet'),
              ' option. You can also add this to your ',
              pre('cucumber.yml:')
            ],
            [pre('default: --publish-quiet')]
          ],
          io
        )
      end
      # rubocop:enable Metrics/MethodLength

      def highlight(text)
        [text, :cyan]
      end

      def link(text)
        [text, :cyan, :bold, :underline]
      end

      def pre(text)
        [text, :bold]
      end
    end
  end
end
