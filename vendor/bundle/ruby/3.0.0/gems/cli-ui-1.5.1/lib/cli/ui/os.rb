require 'rbconfig'

module CLI
  module UI
    module OS
      # Determines which OS is currently running the UI, to make it easier to
      # adapt its behaviour to the features of the OS.
      def self.current
        @current_os ||= case RbConfig::CONFIG['host_os']
        when /darwin/
          Mac
        when /linux/
          Linux
        else
          if RUBY_PLATFORM !~ /cygwin/ && ENV['OS'] == 'Windows_NT'
            Windows
          else
            raise "Could not determine OS from host_os #{RbConfig::CONFIG["host_os"]}"
          end
        end
      end

      class Mac
        class << self
          def supports_emoji?
            true
          end

          def supports_color_prompt?
            true
          end

          def supports_arrow_keys?
            true
          end

          def shift_cursor_on_line_reset?
            false
          end
        end
      end

      class Linux < Mac
      end

      class Windows
        class << self
          def supports_emoji?
            false
          end

          def supports_color_prompt?
            false
          end

          def supports_arrow_keys?
            false
          end

          def shift_cursor_on_line_reset?
            true
          end
        end
      end
    end
  end
end
