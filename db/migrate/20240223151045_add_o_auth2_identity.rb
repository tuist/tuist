class AddOAuth2Identity < ActiveRecord::Migration[7.1]
  def change
    create_table(:oauth2_identities) do |t|
      t.integer(:provider, default: 0, null: false)
      t.references(:user, null: false)
      t.string(:id_in_provider, null: false)
    end
    add_index(:oauth2_identities, [:provider, :id_in_provider, :user_id], unique: true)
    add_index(:oauth2_identities, [:provider, :id_in_provider], unique: true)
  end
end
