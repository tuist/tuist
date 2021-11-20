# frozen_string_literal: true

class AddOrganizationsTable < ActiveRecord::Migration[6.1]
  def change
    create_table(:organizations) do |t|
      t.timestamps(null: false)
    end
  end
end
