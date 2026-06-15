defmodule Tuist.Repo.Migrations.CreateKuraMeshCertificateAuthorities do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    create table(:kura_mesh_certificate_authorities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :certificate_pem, :text, null: false
      add :encrypted_private_key, :binary, null: false
      add :not_after, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:kura_mesh_certificate_authorities, [:account_id])
  end
end
