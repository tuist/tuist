defmodule Atlas.Repo.Migrations.AddTimeOffApprovals do
  use Ecto.Migration

  def up do
    alter table(:time_off_bookings) do
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :timestamptz
      modify :status, :string, null: false, default: "pending"
    end

    create index(:time_off_bookings, [:reviewed_by_id])
    drop constraint(:time_off_bookings, :time_off_bookings_status)
    execute "UPDATE time_off_bookings SET status = 'approved' WHERE status = 'booked'"

    create constraint(:time_off_bookings, :time_off_bookings_status,
             check: "status IN ('pending', 'approved', 'rejected', 'cancelled')"
           )

    drop index(:time_off_bookings, [:starts_on, :ends_on])

    create index(:time_off_bookings, [:starts_on, :ends_on],
             where: "status IN ('pending', 'approved')"
           )

    # Existing executives must receive the permission without a production seed run.
    execute """
    UPDATE roles SET scopes = ARRAY(
      SELECT DISTINCT scope FROM unnest(scopes || ARRAY['time_off_approvals:read', 'time_off_approvals:write']::varchar[]) AS scope
    ), updated_at = now()
    WHERE slug = 'executive'
    """
  end

  def down do
    execute """
    UPDATE roles SET scopes = array_remove(array_remove(scopes, 'time_off_approvals:read'), 'time_off_approvals:write'), updated_at = now()
    """

    drop index(:time_off_bookings, [:starts_on, :ends_on])
    drop constraint(:time_off_bookings, :time_off_bookings_status)

    execute "UPDATE time_off_bookings SET status = 'cancelled' WHERE status = 'rejected'"

    execute "UPDATE time_off_bookings SET status = 'booked' WHERE status IN ('pending', 'approved')"

    create constraint(:time_off_bookings, :time_off_bookings_status,
             check: "status IN ('booked', 'cancelled')"
           )

    create index(:time_off_bookings, [:starts_on, :ends_on], where: "status = 'booked'")

    drop index(:time_off_bookings, [:reviewed_by_id])

    alter table(:time_off_bookings) do
      remove :reviewed_by_id
      remove :reviewed_at
      modify :status, :string, null: false, default: "booked"
    end
  end
end
