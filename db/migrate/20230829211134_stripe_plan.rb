class StripePlan < ActiveRecord::Migration[7.0]
  def change
    add_column(:accounts, :customer_id, :string, default: nil)
    add_column(:accounts, :plan, :integer, default: nil)
  end
end
