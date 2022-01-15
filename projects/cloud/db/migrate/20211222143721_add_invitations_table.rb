# frozen_string_literal: true

class AddInvitationsTable < ActiveRecord::Migration[6.1]
  def change
    create_table(:invitations) do |t|
      t.references(:inviter, polymorphic: true, null: false)
      t.string(:invitee_email, null: false)
      t.references(:organization, null: false)
      t.string(:token, index: { unique: true }, null: false, limit: 100)
      t.timestamps(null: false)
    end
  end
end
