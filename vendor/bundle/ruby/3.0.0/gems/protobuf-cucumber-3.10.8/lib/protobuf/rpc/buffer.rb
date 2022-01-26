module Protobuf
  module Rpc
    class Buffer

      attr_accessor :mode, :data, :size

      MODES = [:read, :write].freeze

      # constantize this so we don't re-initialize the regex every time we need it
      SIZE_REGEX = /^\d+-/

      def initialize(mode = :read)
        @flush = false
        @data = ""
        @size = 0
        self.mode = mode
      end

      def mode=(mode)
        @mode =
          if MODES.include?(mode)
            mode
          else
            :read
          end
      end

      def write(force_mode = true)
        if force_mode && reading?
          self.mode = :write
        elsif !force_mode && reading?
          fail 'You chose to write the buffer when in read mode'
        end

        @size = @data.length
        "#{@size}-#{@data}"
      end

      def <<(data)
        @data << data
        if reading?
          get_data_size
          check_for_flush
        end
      end

      def set_data(data) # rubocop:disable Style/AccessorMethodName
        @data = data.to_s
        @size = @data.size
      end

      def reading?
        mode == :read
      end

      def writing?
        mode == :write
      end

      def flushed?
        @flush
      end

      def get_data_size # rubocop:disable Style/AccessorMethodName
        if @size == 0 || @data.match(SIZE_REGEX)
          sliced_size = @data.slice!(SIZE_REGEX)
          @size = sliced_size.delete('-').to_i unless sliced_size.nil?
        end
      end

      private

      def check_for_flush
        @flush = true if !@size.nil? && @data.length == @size
      end
    end
  end
end
