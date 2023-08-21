# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def after_sign_up_path_for(resource)
      AuthController.new.after_auth_path(session, resource, root_path)
    end

    def after_inactive_sign_up_path_for(resource)
      AuthController.new.after_auth_path(session, resource, root_path)
    end
  end
end
