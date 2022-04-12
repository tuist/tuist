# frozen_string_literal: true

class AddCommandEventsTable < ActiveRecord::Migration[7.0]
  def change
    create_table(:command_events) do |t|
      t.string(:name)
      t.string(:subcommand)
      t.string(:command_arguments)
      t.integer(:duration)
      t.string(:client_id)
      t.string(:tuist_version)
      t.string(:swift_version)
      t.string(:macos_version)
      t.references(:project, null: false)
      t.timestamps
    end
  end
end
