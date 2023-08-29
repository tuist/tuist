# frozen_string_literal: true

class APIController < ApplicationController
  module Error
    class Unauthorized < CloudError
      def message
        "No auth token found. Authenticate with the `tuist cloud auth` command or via the `TUIST_CONFIG_CLOUD_TOKEN` environment variable."
      end

      def status_code
        :unauthorized
      end
    end
  end

  skip_before_action :authenticate_user!
  before_action :authenticate_user_from_token!

  def authenticate_user_from_token!
    authenticate_or_request_with_http_token do |token, options|
      begin
        user = User.find_by!(token: token)
      rescue ActiveRecord::RecordNotFound
        @project = Project.find_by!(token: token)
      rescue ActiveRecord::RecordNotFound
        raise Error::Unauthorized.new
      end
      if user
        sign_in(user, store: false)
      else
        @project
      end
    end
  end

  rescue_from(CloudError) do |error, obj, args, ctx, field|
    render(
      json: { message: error.message },
      status: error.status_code
    )
  end
end
