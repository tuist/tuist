# frozen_string_literal: true
class AddTokenAndRepositoryColumnsToProjects < ActiveRecord::Migration[6.1]
  def change
    change_table("projects", bulk: true) do |t|
      t.string(:repository_full_name, null: false, limit: 30)
      t.string(:api_token, null: false, limit: 30)
    end

    add_index(:projects, :api_token, unique: true)
  end
end
