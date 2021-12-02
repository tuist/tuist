# frozen_string_literal: true

class AddLastVisitedProjectToUser < ActiveRecord::Migration[6.1]
  def change
    change_table(:users) do |t|
      t.references(:last_visited_project, foreign_key: { to_table: :projects })
    end
  end
end
