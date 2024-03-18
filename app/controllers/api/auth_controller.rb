# frozen_string_literal: true

module API
  class AuthController < APIController
    skip_before_action :authenticate_user_or_project!

    def device_code
      device_code = DeviceCode.find_by(code: params[:device_code])
      if device_code.nil? || !device_code.authenticated
        render(json: {}, status: :accepted)
      elsif device_code.created_at < 5.minutes.ago
        render(json: { message: "Device code expired" }, status: :bad_request)
      else
        render(json: { token: device_code.user.token }, status: :ok)
      end
    end
  end
end
