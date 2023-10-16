class AddIsCiToCommandEvents < ActiveRecord::Migration[7.0]
  def change
    change_table(:command_events) do |t|
      t.boolean(:is_ci, default: false)
    end
  end
end
