# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def after_sign_up_path_for(resource)
      if session["is_cli_authenticating"]
        CliAuthService.call(user: current_user)
        session["is_cli_authenticating"] = false
        '/auth/cli/success'
      else
        root_path + "get-started"
      end
    end

    def after_inactive_sign_up_path_for(resource)
      if session["is_cli_authenticating"]
        CliAuthService.call(user: current_user)
        session["is_cli_authenticating"] = false
        '/auth/cli/success'
      else
        root_path + "get-started"
      end
    end
  end
end
