# frozen_string_literal: true

class Invitation < ApplicationRecord
  # Associations
  belongs_to :inviter, foreign_key: :inviter_id, class_name: "User", optional: false
  belongs_to :organization, optional: false
end
