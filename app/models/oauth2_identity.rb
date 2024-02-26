# frozen_string_literal: true

class Oauth2Identity < ApplicationRecord
  enum provider: [:github, :okta]

  belongs_to :user, optional: false
end
