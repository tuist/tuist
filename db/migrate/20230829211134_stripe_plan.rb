class StripePlan < ActiveRecord::Migration[7.0]
  def change
    add_column(:accounts, :customer_id, :string, default: nil)
  end
end
