# frozen_string_literal: true

require "api_token_strategy"

Warden::Strategies.add(:api_token, APITokenStrategy)
