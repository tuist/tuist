defmodule Atlas.Repo.Migrations.AddUploadedLettersToPostal do
  use Ecto.Migration

  def up do
    alter table(:letters) do
      modify :recipient_name, :string, null: true
      modify :recipient_street, :string, null: true
      modify :recipient_postal_code, :string, null: true
      modify :recipient_city, :string, null: true
      modify :recipient_country, :string, null: true, default: "DE"
    end

    drop constraint(:letters, :letters_kind_check)

    create constraint(:letters, :letters_kind_check,
             check: "kind IN ('tax_certificate_request', 'uploaded_letter')"
           )
  end

  def down do
    execute("DELETE FROM letters WHERE kind = 'uploaded_letter'")

    drop constraint(:letters, :letters_kind_check)

    create constraint(:letters, :letters_kind_check, check: "kind IN ('tax_certificate_request')")

    alter table(:letters) do
      modify :recipient_name, :string, null: false
      modify :recipient_street, :string, null: false
      modify :recipient_postal_code, :string, null: false
      modify :recipient_city, :string, null: false
      modify :recipient_country, :string, null: false, default: "DE"
    end
  end
end
