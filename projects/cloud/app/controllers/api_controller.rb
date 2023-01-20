# frozen_string_literal: true

class APIController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :authenticate_user_from_token!

  def authenticate_user_from_token!
    authenticate_or_request_with_http_token do |token, options|
      begin
        user = User.find_by!(token: token)
      rescue ActiveRecord::RecordNotFound
        @project = Project.find_by!(token: token)
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
      json: { errors: [{ message: error.message, code: :bad_request }], status: :bad_request },
      status: :bad_request)
  end
end
