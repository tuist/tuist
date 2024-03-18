class AddDeviceCode < ActiveRecord::Migration[7.1]
  def change
    create_table :device_codes do |t|
      t.string(:code, null: false)
      t.boolean(:authenticated, default: false)
      t.timestamps(null: false)
    end

    add_reference(:device_codes, :user, foreign_key: true, null: true)
  end
end
