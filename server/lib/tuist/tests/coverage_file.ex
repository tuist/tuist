defmodule Tuist.Tests.CoverageFile do
  @moduledoc """
  One source file's coverage for a test run, from any build system
  (`build_system`). `is_test` marks test code (compiled only by test bundles),
  which is kept but left out of every coverage figure. `scope_kind` and
  `scope_id` say whose coverage the row is: the whole `run`, or a `target`,
  `suite` or `test` once tests are attributed. `evidence_kind` is `observed`
  for coverage measured in this run, `cached` for a test result a build system
  reused on identical inputs, and `carried` for evidence reused from an earlier
  run. `in_repository` is whether the path is repository-relative and Git
  knows its contents (`git_blob_id`): only those files can back evidence.

  `line_numbers` lists the file's executable lines, ascending, and
  `execution_counts` how many times each ran. The `function_*` arrays describe
  the file's functions, index by index. A sharded run has a row per shard that
  compiled the file; readers merge them. Rows written by one report share
  `inserted_at`, and only each shard's latest report counts, so a retried or
  reprocessed shard replaces what it reported before. `partial` is whether the
  shard left tests out on purpose. `git_commit_sha` is the run's commit, so a
  commit's coverage is read straight off its rows.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "coverage_files" do
    field :test_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :build_system, Ch, type: "LowCardinality(String)", default: "xcode"
    field :shard_index, Ch, type: "UInt32", default: 0
    field :partial, :boolean, default: false
    field :scope_kind, Ch, type: "LowCardinality(String)", default: "run"
    field :scope_id, Ch, type: "String", default: ""
    field :evidence_kind, Ch, type: "LowCardinality(String)", default: "observed"
    field :path, Ch, type: "String"
    field :in_repository, :boolean, default: true
    field :git_blob_id, Ch, type: "String"
    field :targets, Ch, type: "Array(LowCardinality(String))"
    field :is_test, :boolean, default: false
    field :git_commit_sha, Ch, type: "String", default: ""
    field :covered_lines, Ch, type: "UInt32"
    field :executable_lines, Ch, type: "UInt32"
    field :line_numbers, Ch, type: "Array(UInt32)"
    field :execution_counts, Ch, type: "Array(UInt64)"
    field :covered_branches, Ch, type: "UInt32", default: 0
    field :total_branches, Ch, type: "UInt32", default: 0
    field :branch_line_numbers, Ch, type: "Array(UInt32)"
    field :branch_covered, Ch, type: "Array(UInt32)"
    field :branch_total, Ch, type: "Array(UInt32)"
    field :function_names, Ch, type: "Array(String)"
    field :function_line_numbers, Ch, type: "Array(UInt32)"
    field :function_execution_counts, Ch, type: "Array(UInt64)"
    field :function_covered_lines, Ch, type: "Array(UInt32)"
    field :function_executable_lines, Ch, type: "Array(UInt32)"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end
end
