# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!

  def authenticate
    if current_user.nil?
      session["is_cli_authenticating"] = true
      authenticate_user!
    end

    redirect_to(
      "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}",
      allow_other_host: true,
    )
  end
end
