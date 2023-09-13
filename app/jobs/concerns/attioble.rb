# frozen_string_literal: true

module Attioble
  extend ActiveSupport::Concern

  included do
    def send_attio_request(method, path, **kwargs)
      url = URI.parse("https://api.attio.com").merge(path)
      http = HTTPX.with(headers: {
        "content-type" => "application/json",
        "authorization" => "Bearer #{Environment.attio_api_key}",
      })
      response = http.send(method, url, **kwargs)
      error = response.error
      throw(error) unless error.nil?
      response
    end
  end
end
