# typed: ignore
# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def after_sign_up_path_for(resource)
      AuthController.new.after_auth_path(session, resource, root_path, stored_location_for(:user))
    end

    def after_inactive_sign_up_path_for(resource)
      AuthController.new.after_auth_path(session, resource, root_path, stored_location_for(:user))
    end
  end
end
