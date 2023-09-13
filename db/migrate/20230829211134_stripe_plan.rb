class StripePlan < ActiveRecord::Migration[7.0]
  def change
    add_column(:accounts, :customer_id, :string, default: nil)
    add_column(:accounts, :plan, :integer, default: nil)
    add_index(:accounts, :customer_id, unique: true)
  end
end
