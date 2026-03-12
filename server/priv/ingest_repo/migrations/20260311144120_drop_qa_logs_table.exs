defmodule Tuist.IngestRepo.Migrations.DropQaLogsTable do
  use Ecto.Migration

  def up do
    drop_if_exists table(:qa_logs)
  end

  def down do
    # QA feature has been removed; no rollback provided
    :ok
  end
end
