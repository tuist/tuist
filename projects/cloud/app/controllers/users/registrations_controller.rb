# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::OmniauthCallbacksController
    def create
      super
      UserCreateService.call(email: resource.email)
    end
  end
end
