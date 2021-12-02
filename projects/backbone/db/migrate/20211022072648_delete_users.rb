# frozen_string_literal: true

class DeleteUsers < ActiveRecord::Migration[6.0]
  def change
    drop_table(:users)
    drop_table(:authorizations)
  end
end
