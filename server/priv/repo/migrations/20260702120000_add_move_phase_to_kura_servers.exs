defmodule Tuist.Repo.Migrations.AddMovePhaseToKuraServers do
  @moduledoc """
  A warm-handoff move relocates an account's Kura server between boxes of a
  region: a second server row (the target) is provisioned on the new box and
  warmed from the source, then the two are relabeled so the target takes over
  and the source drains. `move_phase` distinguishes the roles so both rows can
  coexist for one `(account, region)` during a move, while the region still
  admits a single steady-state server.

      none       (0) - the steady-state server; owns the customer host (default)
      moving_in  (1) - a target being warmed on a new box (no customer host yet)
      moving_out (2) - the former source, draining after the target took over

  Promotion is a single relabel: source `none -> moving_out`, target
  `moving_in -> none`. `target_node` pins a `moving_in` target to the
  destination box (a `kubernetes.io/hostname` nodeSelector); null on
  steady-state rows.

  The uniqueness index gains `move_phase`, so at most one row per phase per
  `(account, region)` non-destroyed: a `none` owner coexists with a `moving_in`
  target (warming) or a `moving_out` source (draining), but two `none` rows
  still conflict, keeping one steady-state server per region.
  """
  use Ecto.Migration

  @destroyed_status 4

  def up do
    # excellent_migrations:safety-assured-for-next-line column_added_with_default
    alter table(:kura_servers) do
      add :move_phase, :integer, null: false, default: 0
      add :target_node, :string
    end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE kura_servers ADD CONSTRAINT kura_servers_move_phase_valid CHECK (move_phase IN (0, 1, 2))"
    )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop unique_index(:kura_servers, [:account_id, :region],
           name: :kura_servers_account_region_active_index
         )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :kura_servers,
             [:account_id, :region, :move_phase],
             name: :kura_servers_account_region_move_phase_active_index,
             where: "status <> #{@destroyed_status}"
           )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop unique_index(:kura_servers, [:account_id, :region, :move_phase],
           name: :kura_servers_account_region_move_phase_active_index
         )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :kura_servers,
             [:account_id, :region],
             name: :kura_servers_account_region_active_index,
             where: "status <> #{@destroyed_status}"
           )

    drop constraint(:kura_servers, :kura_servers_move_phase_valid)

    alter table(:kura_servers) do
      remove :move_phase
    end
  end
end
