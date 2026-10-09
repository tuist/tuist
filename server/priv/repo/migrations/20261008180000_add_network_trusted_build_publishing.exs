defmodule Tuist.Repo.Migrations.AddNetworkTrustedBuildPublishing do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :network_trusted_builds, :boolean, null: false, default: false
    end
  end
end
