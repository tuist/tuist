# frozen_string_literal: true

class Invitation < ApplicationRecord
  # Associations
  belongs_to :inviter, foreign_key: :inviter_id, class_name: "User", optional: false
  belongs_to :organization, optional: false

  def as_json(options = {})
    super(options.merge(only: [:id, :invitee_email, :organization_id])).merge({inviter: inviter})
  end
end
