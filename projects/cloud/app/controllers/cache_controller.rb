# frozen_string_literal: true

class CacheController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :authenticate_user_from_token!

  def cache
  end

  def authenticate_user_from_token!
    authenticate_or_request_with_http_token do |token, options|
      user = User.find_by!(token: token)
      if user
        sign_in user, store: false
        true
      else
        false
      end
    end
  end
end
