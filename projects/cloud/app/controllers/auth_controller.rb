# frozen_string_literal: true

require "net/http"

class AuthController < ApplicationController
  def authenticate
    response = Net::HTTP.get_response(URI.parse("http://127.0.0.1:4545/auth?token=1234&account=my_account"))
    render html: response.body.html_safe
  end
end
