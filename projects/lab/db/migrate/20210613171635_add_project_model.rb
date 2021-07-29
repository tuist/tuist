# frozen_string_literal: true
class AddProjectModel < ActiveRecord::Migration[6.1]
  def change
    create_table(:projects) do |t|
      t.string(:name, null: false, limit: 30)
      t.references(:account, null: false)
      t.timestamps
    end
  end
end
