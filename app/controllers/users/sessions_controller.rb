# frozen_string_literal: true

module Users
  class SessionsController < Devise::SessionsController
    def after_sign_in_path_for(resource)
      AuthController.new.after_auth_path(session, resource, root_path, stored_location_for(:user))
    end

    def after_sign_out_path_for(resource)
      new_session_path(resource)
    end
  end
end
