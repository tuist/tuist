defmodule Tuist.IngestRepo.Migrations.CompressAndExpireBuildStepLogs do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_steps
      MODIFY COLUMN log String DEFAULT '' CODEC(ZSTD(3)) TTL inserted_at + INTERVAL 30 DAY,
      MODIFY COLUMN log_truncated Bool DEFAULT false TTL inserted_at + INTERVAL 30 DAY
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_steps MODIFY COLUMN log_truncated REMOVE TTL"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_steps MODIFY COLUMN log REMOVE TTL"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_steps MODIFY COLUMN log REMOVE CODEC"
  end
end
