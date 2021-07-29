# frozen_string_literal: true
class AdminPolicy < ApplicationPolicy
  def access?
    user&.email == "pedro@ppinera.es" || Rails.env.development?
  end
end
