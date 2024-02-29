# frozen_string_literal: true

class DestroyOauth2Users < ApplicationService
  attr_reader :ids, :provider

  def initialize(ids:, provider:)
    super()
    @ids = ids
    @provider = provider
  end

  def call
    user_ids = Oauth2Identity.where(provider: provider.to_s, id_in_provider: ids).pluck(:user_id)
    User.where(id: user_ids).destroy_all
  end
end
