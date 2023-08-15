# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::SessionsController
    def new
      @user = UserCreateService.call(email: params[:email], password: params[:password])
      super
    end

    def after_sign_in_path_for(resource)
      if session["is_cli_authenticating"]
        "http://127.0.0.1:4545/auth?token=#{current_user.token}&account=#{current_user.account.name}"
      else
        root_path
      end
    end
  end
end
