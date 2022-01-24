# frozen_string_literal: true

require "net/http"

class AuthController < ApplicationController
  def authenticate
    response = Net::HTTP.get_response(URI.parse("http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}"))
    render(html: response.body.html_safe)
  end
end
