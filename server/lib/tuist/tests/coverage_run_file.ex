defmodule Tuist.Tests.CoverageRunFile do
  @moduledoc """
  One source file's coverage in one shard report of a test run, from any build
  system (`build_system`): what the run measured. The file's version, which
  doesn't change between runs (its blob, executable lines and functions), is
  stored once per week in `Tuist.Tests.CoverageFileLayout`, named by
  `layout_id` and `epoch` (the first day of the path's week the report was
  written in, `Tuist.Tests.Coverage.layout_epoch/2`).

  `execution_counts` holds how many times each of the layout's lines ran,
  index by index, and is empty when none did; the function arrays hold the
  layout's functions' calls and covered lines the same way. Counts are
  UInt32, capped at its maximum (about 4.3 billion), which no line reaches
  in practice. `covered_lines`
  and `executable_lines` are the report's counts, which are all a file
  without line data (its archive entry was missing) has. `is_test` marks test
  code, kept but left out of every figure. `in_repository` is whether the path
  is repository-relative and Git knows its contents.

  A sharded run has a row per shard that compiled the file. Rows written by
  one report share `inserted_at`, and only each shard's latest report counts,
  so a retried shard replaces what it reported before. `partial` is whether
  the shard left tests out on purpose. `Tuist.Tests.Coverage.report_files_for_runs/3`
  joins the rows with their layouts.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_run_files" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :shard_index, Ch, type: "UInt32", default: 0
    field :path, Ch, type: "String"
    # Derived by ClickHouse from `path` and `inserted_at` (an ALIAS column).
    field :epoch, Ch, type: "Date", default: :database
    field :layout_id, Ch, type: "UInt32"
    field :build_system, Ch, type: "LowCardinality(String)", default: "xcode"
    field :partial, :boolean, default: false
    field :in_repository, :boolean, default: true
    field :is_test, :boolean, default: false
    field :targets, Ch, type: "Array(LowCardinality(String))"
    field :git_commit_sha, Ch, type: "String", default: ""
    field :covered_lines, Ch, type: "UInt32"
    field :executable_lines, Ch, type: "UInt32"
    field :execution_counts, Ch, type: "Array(UInt32)"
    field :function_execution_counts, Ch, type: "Array(UInt32)"
    field :function_covered_lines, Ch, type: "Array(UInt32)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
