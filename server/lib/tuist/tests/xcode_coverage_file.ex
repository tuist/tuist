defmodule Tuist.Tests.XcodeCoverageFile do
  @moduledoc """
  One source file's line coverage for a test run, read from the run's result
  bundle.

  `line_numbers` lists the file's executable lines, ascending, and
  `execution_counts` how many times each ran. The `function_*` arrays describe
  the file's functions, index by index. A sharded run has a row per shard that
  compiled the file; readers merge them.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "xcode_coverage_files" do
    field :test_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :path, Ch, type: "String"
    field :git_blob_id, Ch, type: "String"
    field :targets, Ch, type: "Array(LowCardinality(String))"
    field :covered_lines, Ch, type: "UInt32"
    field :executable_lines, Ch, type: "UInt32"
    field :line_numbers, Ch, type: "Array(UInt32)"
    field :execution_counts, Ch, type: "Array(UInt64)"
    field :function_names, Ch, type: "Array(String)"
    field :function_line_numbers, Ch, type: "Array(UInt32)"
    field :function_execution_counts, Ch, type: "Array(UInt64)"
    field :function_covered_lines, Ch, type: "Array(UInt32)"
    field :function_executable_lines, Ch, type: "Array(UInt32)"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end
end
