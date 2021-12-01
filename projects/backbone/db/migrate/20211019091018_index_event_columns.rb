# frozen_string_literal: true

class IndexEventColumns < ActiveRecord::Migration[6.0]
  def change
    add_index(:command_events, :client_id)
    add_index(:command_events, :name)
    add_index(:command_events, :subcommand)
    add_index(:command_events, :tuist_version)
    add_index(:command_events, :macos_version)
    add_index(:command_events, :is_ci)
  end
end
