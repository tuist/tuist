# frozen_string_literal: true

class AddAccountsTable < ActiveRecord::Migration[6.1]
  def change
    create_table(:accounts) do |t|
      t.string(:name, limit: 40, null: false)
      t.references(:owner, polymorphic: true, null: false)
      t.timestamps(null: false)
    end

    # rubocop:disable Rails/NotNullColumn
    add_reference(:projects, :account, foreign_key: true, null: false)

    add_index(:accounts, :name, unique: true)
    add_index(:projects, [:name, :account_id], unique: true)
    add_index(:accounts, [:owner_id, :owner_type], unique: true)
  end
end
