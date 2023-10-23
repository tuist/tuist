# frozen_string_literal: true

class APIController < ActionController::Base
  module Error
    class Unauthorized < CloudError
      def message
        "No auth token found. Authenticate with the `tuist cloud auth` command "\
          "or via the `TUIST_CONFIG_CLOUD_TOKEN` environment variable."
      end

      def status_code
        :unauthorized
      end
    end
  end

  # The API is used by a trusted client (CLI) that authenticates
  # using a token so this is not necessary.
  protect_from_forgery with: :null_session
  before_action :authenticate_user_from_token!

  def authenticate_user_from_token!
    authenticate_or_request_with_http_token do |token, _options|
      user = nil
      begin
        user = User.find_by!(token: token)
      rescue ActiveRecord::RecordNotFound
        begin
          @project = Project.find_by!(token: token)
        rescue ActiveRecord::RecordNotFound
          raise Error::Unauthorized
        end
      end
      if user
        sign_in(user, store: false)
      else
        @project
      end
    end
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    render(
      json: { message: error.message },
      status: error.status_code,
    )
  end
end
