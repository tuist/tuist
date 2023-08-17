# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!

  def authenticate
    if current_user.nil?
      session["is_cli_authenticating"] = true
      authenticate_user!
    end

    CliAuthService.call(user: current_user)

    session["is_cli_authenticating"] = false

    redirect_to("/auth/cli/success")
  end

  def cli_success
    render "auth/cli/success"
  end
end
