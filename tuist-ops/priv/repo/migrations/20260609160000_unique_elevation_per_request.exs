defmodule TuistOps.Repo.Migrations.UniqueElevationPerRequest do
  @moduledoc """
  One Request must yield at most one Elevation.

  The original `create_tailscale_jit_tables` migration indexed
  `request_id` non-uniquely, which left the door open to:
  two near-simultaneous "Approve" clicks on the same Slack card
  → both pass the in-transaction `Request.status == "pending"`
  check → both insert an Elevation row → two active elevations
  for the same request. Slack only shows one card (one
  message_ts), and revoke only flips one row; the other
  elevation lingers undetected.

  Replacing the non-unique index with a unique one is the DB-side
  safety net. The approve path also takes a `SELECT ... FOR
  UPDATE` lock on the Request row now, which is the optimistic
  path — concurrent approves serialise on the lock and only the
  first one proceeds. The unique constraint is the belt-and-
  suspenders if the lock is ever bypassed (long-lived
  transaction, future code path that skips the lock, etc.).

  Tiny table (handful of rows in tuist-ops Postgres) so the
  non-concurrent index op is a sub-second blip.
  """
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop index(:tailscale_jit_elevations, [:request_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:tailscale_jit_elevations, [:request_id])
  end
end
