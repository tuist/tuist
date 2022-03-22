# frozen_string_literal: true

class AddAcceptedInvitationColumn < ActiveRecord::Migration[7.0]
  def change
    add_column(:invitations, :accepted, :bool, default: false)
    change_column_null(:invitations, :accepted, false, false)
    add_index(:invitations, [:invitee_email, :organization_id], unique: true)
  end
end
