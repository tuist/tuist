defmodule TuistOps.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's framework migration. Creates `oban_jobs` + related tables
  # the RevertWorker (the only worker in this app) needs to exist
  # before Oban.start_link/1 will succeed. Runs before the
  # `create_tailscale_jit_tables` migration via earlier timestamp.
  def up, do: Oban.Migrations.up()
  def down, do: Oban.Migrations.down()
end
