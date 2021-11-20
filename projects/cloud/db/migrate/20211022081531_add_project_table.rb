# frozen_string_literal: true

class AddProjectTable < ActiveRecord::Migration[6.1]
  def change
    create_table(:projects) do |t|
      t.string(:name, limit: 40, null: false)
      t.string(:token, index: { unique: true }, null: false, limit: 100)
      t.timestamps(null: false)
    end
  end
end
