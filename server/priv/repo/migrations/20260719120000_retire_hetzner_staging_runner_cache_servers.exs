defmodule Tuist.Repo.Migrations.RetireHetznerStagingRunnerCacheServers do
  use Ecto.Migration

  @retired_region "hetzner-staging-runners"
  @destroying_status 3
  @destroyed_status 4

  def up do
    # This data migration intentionally targets the exact retired fleet rows.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    execute("""
    UPDATE kura_servers
    SET status = #{@destroying_status}, updated_at = NOW()
    WHERE region = '#{@retired_region}'
      AND status <> #{@destroyed_status}
    """)
  end

  def down do
    :ok
  end
end
