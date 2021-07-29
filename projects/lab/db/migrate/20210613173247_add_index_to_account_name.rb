# frozen_string_literal: true
class AddIndexToAccountName < ActiveRecord::Migration[6.1]
  def change
    change_table(:accounts) do |t|
      t.index(:name, unique: true)
    end
  end
end
