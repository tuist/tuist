# frozen_string_literal: true

class AddMachineNameToCommandEvent < ActiveRecord::Migration[6.0]
  def change
    add_column(:command_events, :machine_hardware_name, :string)
  end
end
