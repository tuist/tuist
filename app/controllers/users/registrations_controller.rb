# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    protected

    def after_sign_up_path_for(resource)
      "http://127.0.0.1:4545/auth?token=#{resource.token}&account=#{resource.account.name}"
    end

    def after_inactive_sign_up_path_for(resource)
      "http://127.0.0.1:4545/auth?token=#{resource.token}&account=#{resource.account.name}"
    end
  end
end
