defmodule Tuist.Repo.Migrations.AddSsoProofToDeviceCodes do
  use Ecto.Migration

  def change do
    # The browser session that approves a device code records which single
    # sign-on it proved, so the CLI tokens issued for the code can carry it.
    # No backfill: codes live five minutes, and older approvals prove nothing.
    alter table(:device_codes) do
      add :auth_provider, :string
      add :auth_provider_organization_id, :string
      add :auth_organization_id, references(:organizations, on_delete: :nilify_all)
    end
  end
end
