# frozen_string_literal: true

class AuthorizationAddService < ApplicationService
  def initialize(user:, data:)
    @user = user
    @data = data
  end

  def call
    @user.authorizations.build({
      provider: @data["provider"],
      uid: @data["uid"],
      # token: data['credentials']['token'],
      # secret: data['credentials']['secret'],
      # refresh_token: data['credentials']['refresh_token'],
      # expires: data['credentials']['expires'],
      # expires_at: (Time.at(data['credentials']['expires_at']) rescue nil),
      # Human readable label if a user connects multiple Google accounts
      email: @data["info"]["email"]
    }).save
  end
end
