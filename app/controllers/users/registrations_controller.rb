# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def after_sign_up_path_for(resource)
      if session["is_cli_authenticating"]
        "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}"
      else
        root_path + "get-started"
      end
    end

    def after_inactive_sign_up_path_for(resource)
      if session["is_cli_authenticating"]
        "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}"
      else
        root_path + "get-started"
      end
    end
  end
end
