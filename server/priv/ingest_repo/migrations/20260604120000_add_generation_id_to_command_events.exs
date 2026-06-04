defmodule Tuist.IngestRepo.Migrations.AddGenerationIdToCommandEvents do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE command_events ADD COLUMN IF NOT EXISTS `generation_id` Nullable(UUID)")

    # Bloom filter index for equality lookups (generation_id = 'uuid'), mirroring idx_build_run_id.
    execute(
      "ALTER TABLE command_events ADD INDEX idx_generation_id generation_id TYPE bloom_filter GRANULARITY 8"
    )
  end

  def down do
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_generation_id")
    execute("ALTER TABLE command_events DROP COLUMN IF EXISTS `generation_id`")
  end
end
