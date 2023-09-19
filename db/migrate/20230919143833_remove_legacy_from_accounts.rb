class RemoveLegacyFromAccounts < ActiveRecord::Migration[7.0]
  def change
    remove_column :accounts, :legacy
  end
end
