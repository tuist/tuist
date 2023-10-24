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

  before_action :authenticate_user_from_token!

  # The API is used by a trusted client (CLI) that authenticates
  # using a token so this is not necessary.
  protect_from_forgery with: :null_session

  def authenticate_user_from_token!
    unless user_signed_in? || project_signed_in?
      raise Error::Unauthorized
    end

    # TODO: Deprecate @project, because it doesn't say anything about that being the
    # authenticated project
    @project = current_project
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    render(
      json: { message: error.message },
      status: error.status_code,
    )
  end
end
