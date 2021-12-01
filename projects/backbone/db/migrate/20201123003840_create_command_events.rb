# frozen_string_literal: true

class CreateCommandEvents < ActiveRecord::Migration[6.0]
  def change
    create_table(:command_events) do |t|
      t.string(:name)
      t.string(:subcommand)
      t.json(:params)
      t.integer(:duration)
      t.string(:client_id)
      t.string(:tuist_version)
      t.string(:swift_version)
      t.string(:macos_version)
      t.timestamps
    end
  end
end
