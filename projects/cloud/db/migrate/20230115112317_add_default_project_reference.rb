# frozen_string_literal: true

class AddDefaultProjectReference < ActiveRecord::Migration[7.0]
  def change
    change_table(:s3_buckets) do |t|
      t.references(:default_project, null: true)
    end
  end
end
