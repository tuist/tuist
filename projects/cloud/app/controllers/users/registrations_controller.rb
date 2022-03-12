# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::SessionsController
    def new
      @user = UserCreateService.call(email: params[:email], password: params[:password])
      super
    end
  end
end
