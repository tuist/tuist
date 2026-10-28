defmodule Tuist.IngestRepo.Migrations.AddFilesToCoverageRuns do
  use Ecto.Migration

  # How many files the run's reports listed, test files included. A run whose
  # product code all came from the binary cache without coverage counters lists
  # its test files and measures no product line; the count is what still says
  # it gathered coverage. Rows published before carry 0 and count by their
  # lines alone.
  def change do
    alter table(:coverage_runs) do
      add :files, :UInt32, default: 0
    end
  end
end
