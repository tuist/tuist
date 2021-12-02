# frozen_string_literal: true

class AddIsCiToCommandEvents < ActiveRecord::Migration[6.0]
  def change
    add_column(:command_events, :is_ci, :boolean)
  end
end
