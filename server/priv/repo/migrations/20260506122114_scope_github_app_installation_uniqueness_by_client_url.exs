defmodule Tuist.Repo.Migrations.ScopeGithubAppInstallationUniquenessByClientUrl do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  @moduledoc """
  GitHub installation IDs (and App IDs) are scoped per GitHub instance,
  so two different GHES instances can each emit installation `123`. The
  original schema had a global unique index on `installation_id` alone,
  which would reject the second host's install. Replace it with a
  composite index keyed on `(client_url, installation_id)`, and add the
  same scoping for `app_id` so credentials registered via the manifest
  flow on different GHES instances don't collide either.
  """

  def change do
    drop_if_exists unique_index(:github_app_installations, [:installation_id])
    create unique_index(:github_app_installations, [:client_url, :installation_id])
    create unique_index(:github_app_installations, [:client_url, :app_id])
  end
end
