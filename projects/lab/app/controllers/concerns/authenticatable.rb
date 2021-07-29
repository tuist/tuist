# frozen_string_literal: true
module Authenticatable
  extend ActiveSupport::Concern

  included do
    devise_group :authenticatable, contains: [:user, :project]
  end
end
