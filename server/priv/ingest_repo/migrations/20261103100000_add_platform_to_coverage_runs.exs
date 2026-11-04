defmodule Tuist.IngestRepo.Migrations.AddPlatformToCoverageRuns do
  use Ecto.Migration

  # The platform the run's tests ran on (`ios`, `macos`, …), from the
  # destination the client resolved. Coverage-based test selection only picks a
  # baseline whose runs tested the same platform, since one test can execute
  # different files on each. Empty where the build system has none and on rows
  # published before.
  def change do
    alter table(:coverage_runs) do
      add :platform, :"LowCardinality(String)", default: ""
    end
  end
end
