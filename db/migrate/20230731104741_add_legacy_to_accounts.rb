class AddLegacyToAccounts < ActiveRecord::Migration[7.0]
  def change
    change_table(:accounts) do |t|
      t.boolean(:legacy, null: false, default: true)
    end
  end
end
