# frozen_string_literal: true
# typed: ignore

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def okta
      email = auth_data["info"]["email"]
      provider = :okta
      id_in_provider = auth_data["uid"]
      find_or_create_and_redirect_user(provider: provider, id_in_provider: id_in_provider, email: email)
    end

    def github
      email = auth_data["info"]["email"]
      provider = :github
      id_in_provider = auth_data["uid"]
      find_or_create_and_redirect_user(provider: provider, id_in_provider: id_in_provider, email: email)
    end

    def google_oauth2
      email = auth_data["info"]["email"]
      provider = :google
      id_in_provider = auth_data["uid"]
      find_or_create_and_redirect_user(provider: provider, id_in_provider: id_in_provider, email: email)
    end

    def failure
      redirect_to(root_path)
    end

    def after_sign_in_path_for(resource)
      AuthController.new.after_auth_path(session, resource, root_path, stored_location_for(:user))
    end

    def find_or_create_and_redirect_user(provider:, id_in_provider:, email:)
      @user = UserCreateService.call(email: email, id_in_provider: id_in_provider, provider: provider)
      if @user.persisted?
        sign_in_and_redirect(@user, event: :authentication)
      else
        data = auth_data.except("extra")
        session["devise.oauth.data"] = data
        redirect_to(new_user_registration_url)
      end
    end

    def auth_data
      request.env["omniauth.auth"]
    end
  end
end
