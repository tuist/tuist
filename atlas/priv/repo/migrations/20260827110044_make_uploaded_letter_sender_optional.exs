defmodule Atlas.Repo.Migrations.MakeUploadedLetterSenderOptional do
  use Ecto.Migration

  def up do
    alter table(:letters) do
      modify :account_id, :binary_id, null: true

      modify :sender_name, :string, null: true
      modify :sender_street, :string, null: true
      modify :sender_postal_code, :string, null: true
      modify :sender_city, :string, null: true
      modify :sender_country, :string, null: true, default: "DE"
    end
  end

  def down do
    execute("DELETE FROM letters WHERE kind = 'uploaded_letter' AND account_id IS NULL")

    alter table(:letters) do
      modify :account_id, :binary_id, null: false

      modify :sender_name, :string, null: false
      modify :sender_street, :string, null: false
      modify :sender_postal_code, :string, null: false
      modify :sender_city, :string, null: false
      modify :sender_country, :string, null: false, default: "DE"
    end
  end
end
