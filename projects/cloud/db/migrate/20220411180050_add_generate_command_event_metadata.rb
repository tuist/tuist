# frozen_string_literal: true

class AddGenerateCommandEventMetadata < ActiveRecord::Migration[7.0]
  def change
    create_table(:generate_command_event_metadata) do |t|
      t.text(:all_targets, array: true)
    end
  end
end
