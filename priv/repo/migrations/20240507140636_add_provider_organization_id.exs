defmodule Tuist.Repo.Migrations.AddProviderOrganizationId do
  use Ecto.Migration

  def change do
    alter table(:oauth2_identities) do
      add(:provider_organization_id, :string)
    end

    create index(:oauth2_identities, [:user_id, :provider, :provider_organization_id])

    alter table(:organizations) do
      add(:sso_provider, :integer)
      add(:sso_organization_id, :string)
    end

    create unique_index(:organizations, [:sso_provider, :sso_organization_id])
  end
end
