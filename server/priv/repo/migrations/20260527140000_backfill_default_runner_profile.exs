defmodule Tuist.Repo.Migrations.BackfillDefaultRunnerProfile do
  @moduledoc ~S"""
  Seeds a `default` profile for every account that currently has
  runners enabled (`runner_max_concurrent > 0`), so existing
  customers' workflows can move to `runs-on: tuist-default`
  without first visiting the Profiles UI.

  Defaults to 4 vCPUs / 16 GB — matches the Linux shape we expect
  to be the catalog default. The chart's `runnersFleetLinux.shapes`
  must contain a `{ vcpus: 4, memoryGb: 16 }` entry for the
  resulting profile to actually dispatch; if the chart's catalog
  uses different defaults, edit the constants here and re-run.

  Idempotent: skips accounts that already have any profile.
  """
  use Ecto.Migration

  import Ecto.Query

  alias Tuist.Repo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @default_vcpus 4
  @default_memory_gb 16
  @default_name "default"

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    eligible_account_ids =
      from(a in "accounts",
        left_join: p in "runner_profiles",
        on: p.account_id == a.id,
        where: a.runner_max_concurrent > 0 and is_nil(p.id),
        select: a.id,
        distinct: true
      )
      # excellent_migrations:safety-assured-for-next-line operation_all
      |> Repo.all()

    rows =
      Enum.map(eligible_account_ids, fn account_id ->
        %{
          account_id: account_id,
          name: @default_name,
          vcpus: @default_vcpus,
          memory_gb: @default_memory_gb,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [] do
      # excellent_migrations:safety-assured-for-next-line operation_insert
      Repo.insert_all("runner_profiles", rows, on_conflict: :nothing)
    end
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line operation_delete
    Repo.delete_all(from(p in "runner_profiles", where: p.name == ^@default_name))
  end
end
