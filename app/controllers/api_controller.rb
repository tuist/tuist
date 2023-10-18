# frozen_string_literal: true

class APIController < ApplicationController
  module Error
    class AuthenticatedSubjectNotFound < CloudError
      def message
        "The authentication token is invalid or expired."
      end

      def status_code
        :unauthorized
      end
    end
  end

  # Authentication
  before_action :authenticate!

  # Authorization needs to be after the authentication
  include AuthorizeCurrentSubjectType

  devise_group :subject, contains: [:user, :project]
  helper_method :current_project, :project_signed_in?
  skip_before_action :authenticate_user!

  attr_reader :current_project

  def authenticate!
    authenticate_or_request_with_http_token do |token, _options|
      user = User.find_by(token: token)
      @current_project = Project.find_by(token: token)

      raise Error::AuthenticatedSubjectNotFound if user.nil? && @current_project.nil?

      if user
        sign_in(user, store: false)
      else
        @current_project
      end
    end
  end

  def current_subject
    current_user || current_project
  end

  def project_signed_in?
    current_project.present?
  end

  rescue_from(CloudError) do |error, _obj, _args, _ctx, _field|
    render(
      json: { message: error.message },
      status: error.status_code,
    )
  end
end
