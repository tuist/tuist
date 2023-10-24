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

  before_action :authenticate_user_or_project!

  # The API is used by a trusted client (CLI) that authenticates
  # using a token so this is not necessary.
  protect_from_forgery with: :null_session

  def authenticate_user_or_project!
    raise Error::Unauthorized unless user_signed_in? || project_signed_in?
  end

  # TODO: Deprecate @project, because it doesn't say anything about that being the
  # authenticated project
  def project
    @project ||= current_project
  end

  def current_subject
    @current_subject ||= current_project || current_user
  end

  def current_project
    @current_project ||= fetch_project_from_token
  end

  def current_user
    @current_user ||= fetch_user_from_token
  end

  def fetch_project_from_token
    Project.find_by(token: authorization_token)
  end

  def fetch_user_from_token
    User.find_by(token: authorization_token)
  end

  def authorization_token
    request.headers['Authorization'].to_s.split('Bearer ').last
  end

  def project_signed_in?
    !!current_project
  end

  def user_signed_in?
    !!current_user
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    render(
      json: { message: error.message },
      status: error.status_code,
    )
  end
end
