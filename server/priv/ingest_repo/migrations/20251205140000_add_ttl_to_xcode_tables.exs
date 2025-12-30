defmodule Tuist.IngestRepo.Migrations.AddTtlToXcodeTables do
  use Ecto.Migration

  def up do
    # Add TTL to automatically delete records older than 30 days
    # This prevents unbounded table growth

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MODIFY TTL inserted_at + INTERVAL 30 DAY"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_projects MODIFY TTL inserted_at + INTERVAL 30 DAY"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_graphs MODIFY TTL inserted_at + INTERVAL 30 DAY"
  end

  def down do
    # Remove TTL from tables (keeps all data indefinitely)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets REMOVE TTL"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_projects REMOVE TTL"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_graphs REMOVE TTL"
  end
end
