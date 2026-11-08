defmodule Tuist.IngestRepo.Migrations.AddTestAttributionToBazelInvocationLogs do
  use Ecto.Migration

  # The target label and attempt status of the test result a test.log row came
  # from, so logs can be filtered by target and failed attempts. Empty on
  # progress output, which Bazel does not attribute, and on rows written before.
  # A ClickHouse column default is metadata only: existing parts are not
  # rewritten.
  def change do
    alter table(:bazel_invocation_logs) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :target_label, :string, default: ""
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :status, :"LowCardinality(String)", default: ""
    end
  end
end
