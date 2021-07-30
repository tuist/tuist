# frozen_string_literal: true
class AddAccountModel < ActiveRecord::Migration[6.1]
  def change
    create_table(:accounts) do |t|
      t.string(:name, null: false, limit: 30)
      t.references(:owner, null: false, polymorphic: true)

      t.timestamps
    end
    create_table(:organizations, &:timestamps)
  end
end
