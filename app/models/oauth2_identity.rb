# frozen_string_literal: true

class Oauth2Identity < ApplicationRecord
  enum provider: [:github, :okta, :google]

  belongs_to :user, optional: false
end
