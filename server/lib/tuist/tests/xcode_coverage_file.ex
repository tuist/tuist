defmodule Tuist.Tests.XcodeCoverageFile do
  @moduledoc """
  One source file's line coverage in one Xcode target, as `xccov` reported it
  for a test run. Stored in ClickHouse beside the `Tuist.Tests.Test` it
  belongs to via `test_run_id`.

  A file linked into several targets has a row per target with identical
  counts, which is how `xccov` reports it; per-run totals dedupe by path.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "xcode_coverage_files" do
    field :test_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :target_name, Ch, type: "String"
    field :path, Ch, type: "String"
    field :covered_lines, Ch, type: "UInt32"
    field :executable_lines, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end

  def create_changeset(file, attrs) do
    file
    |> cast(attrs, [:id, :test_run_id, :project_id, :target_name, :path, :covered_lines, :executable_lines, :inserted_at])
    |> validate_required([:id, :test_run_id, :project_id, :target_name, :path, :covered_lines, :executable_lines])
  end
end
