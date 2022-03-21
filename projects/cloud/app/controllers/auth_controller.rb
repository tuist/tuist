# frozen_string_literal: true

class AuthController < ApplicationController
  def authenticate
    redirect_to(
      "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}",
      allow_other_host: true
    )
  end
end
