defmodule Tuist.IngestRepo.Migrations.AddIsQuarantinedToTestCases do
  use Ecto.Migration

  def change do
    alter table(:test_cases) do
      add :is_quarantined, :boolean, default: false
    end
  end
end
