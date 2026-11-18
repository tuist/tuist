defmodule Tuist.Repo.Migrations.AddUserCodeToDeviceCodes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # The short code a person types to approve a device code issued by the
    # standard device flow (RFC 8628). Codes created by the older link-based
    # flow have none.
    alter table(:device_codes) do
      add :user_code, :string
    end

    create unique_index(:device_codes, [:user_code], concurrently: true)
  end
end
