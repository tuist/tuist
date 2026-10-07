defmodule TuistOps.Repo.Migrations.AddGithubLoginToJitTables do
  use Ecto.Migration

  # GitHub organization admin elevations target a GitHub account
  # rather than the requester's tailnet identity, so both the request
  # and the elevation carry the login that is promoted and later
  # demoted. Null for cluster elevations.
  def change do
    alter table(:tailscale_jit_requests) do
      add :github_login, :string
    end

    alter table(:tailscale_jit_elevations) do
      add :github_login, :string
    end
  end
end
