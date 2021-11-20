# frozen_string_literal: true

class Account < ApplicationRecord
  # Associations
  belongs_to :owner, polymorphic: true, optional: false
end
