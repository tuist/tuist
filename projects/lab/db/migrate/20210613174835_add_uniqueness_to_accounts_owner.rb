# frozen_string_literal: true
class AddUniquenessToAccountsOwner < ActiveRecord::Migration[6.1]
  def change
    change_table(:accounts) do |t|
      t.index([:owner_id, :owner_type], unique: true)
    end
  end
end
