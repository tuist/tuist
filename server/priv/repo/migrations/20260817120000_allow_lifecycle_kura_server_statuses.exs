defmodule Tuist.Repo.Migrations.AllowLifecycleKuraServerStatuses do
  use Ecto.Migration

  # Adds the two demand-driven lifecycle statuses:
  #
  #   drain_pending (6) - inactive past its window: the endpoint is unpublished
  #                       and in-flight work is draining before teardown.
  #   archived      (7) - reclaimed: no pod, no endpoint, no local directory.
  #                       Authoritative object storage serves the account.
  #
  # `archived` is deliberately distinct from `destroyed` (4): destroyed is
  # operator-driven teardown and terminal, while archived is a reversible
  # reclamation the next cache demand cold-provisions out of. The partial
  # uniqueness index only excludes destroyed rows, so an archived row keeps
  # owning `(account, region)` and is the row a cold return reuses.
  def up do
    drop constraint(:kura_servers, :kura_servers_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_servers, :kura_servers_status_valid,
             check: "status IN (0, 1, 2, 3, 4, 5, 6, 7)"
           )
  end

  def down do
    drop constraint(:kura_servers, :kura_servers_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_servers, :kura_servers_status_valid,
             check: "status IN (0, 1, 2, 3, 4, 5)"
           )
  end
end
