# frozen_string_literal: true

class AddInvitationIndex < ActiveRecord::Migration[7.0]
  def change
    add_index(:invitations, [:invitee_email, :organization_id], unique: true)
  end
end
