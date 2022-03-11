# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def github
      find_or_create_and_redirect_user
    end

    def gitlab
      find_or_create_and_redirect_user
    end

    def failure
      redirect_to(root_path)
    end

    def find_or_create_and_redirect_user
      @user = UserCreateService.call(email: auth_email, skip_confirmation: true)
      if @user.persisted?
        sign_in_and_redirect(@user, event: :authentication)
      else
        data = auth_data.except("extra")
        session["devise.oauth.data"] = data
        redirect_to(new_user_registration_url)
      end
    end

    def auth_email
      auth_data["info"]["email"]
    end

    def auth_data
      request.env["omniauth.auth"]
    end
  end
end
