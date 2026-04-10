defmodule Tuist.IngestRepo.Migrations.BackfillStateFromIsQuarantined do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE test_cases UPDATE state = 'muted' WHERE is_quarantined = true")
  end

  def down do
    :ok
  end
end
