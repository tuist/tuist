# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::SessionsController
    def new
      @user = UserCreateService.call(email: params[:email], password: params[:password])
      super
    end

    def after_sign_in_path_for(resource)
      root_path
    end
  end
end
