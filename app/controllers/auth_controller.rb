# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!

  def authenticate
    if current_user.nil?
      session["is_cli_authenticating"] = true
      authenticate_user!
    end

<<<<<<< HEAD
    CliAuthService.call(user: current_user)

=======
<<<<<<< Updated upstream
    redirect_to(
      "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}",
      allow_other_host: true,
    )
=======
    CliAuthService.call(user: current_user)

    session["is_cli_authenticating"] = false

>>>>>>> 9231fe0 (Reset cli_authenticating variable after successful authentication)
    redirect_to("/auth/cli/success")
  end

  def cli_success
    render "auth/cli/success"
<<<<<<< HEAD
=======
>>>>>>> Stashed changes
>>>>>>> 9231fe0 (Reset cli_authenticating variable after successful authentication)
  end
end
