# frozen_string_literal: true

require 'base64'

module JWT
  # Base64 helpers
  class Base64
    class << self
      def url_encode(str)
        ::Base64.encode64(str).tr('+/', '-_').gsub(/[\n=]/, '')
      end

      def url_decode(str)
        str += '=' * (4 - str.length.modulo(4))
        ::Base64.decode64(str.tr('-_', '+/'))
      end
    end
  end
end
