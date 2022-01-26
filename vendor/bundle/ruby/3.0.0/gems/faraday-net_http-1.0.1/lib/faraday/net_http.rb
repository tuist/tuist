# frozen_string_literal: true

require_relative 'adapter/net_http'
require_relative 'net_http/version'

module Faraday
  module NetHttp
    Faraday::Adapter.register_middleware(net_http: Faraday::Adapter::NetHttp)
  end
end
