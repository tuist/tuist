defmodule Tuist.Tests.CoverageRun do
  @moduledoc """
  A test run's line coverage totals, merged across its shards, for the
  coverage trend, with what measured them: the build system, the coverage
  tool and its version, the repository's Git object format, the scheme
  (the configuration the figures belong to) and the platform the tests ran
  on, which coverage-based test selection matches baselines by, and how many
  files the reports
  listed, test files included: what says a run gathered coverage when its
  product code all came prebuilt and no product line was measured. Every
  shard report inserts the totals it computed over the shards reported so far. Reports can land in any order, so `version` ranks a
  computation by how many shards it included, then by the newest report it
  saw: the most complete one wins.

  `report_shards` and `report_inserted_at` pin the report of each shard the
  totals cover, by the `inserted_at` its `coverage_run_files` rows share:
  every replica held them when the row was written, and readers take those
  rows (`Tuist.Tests.Coverage.report_files_for_runs/3`). Rows written before
  the pins existed have none, and readers take each shard's newest report.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_runs" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :build_system, Ch, type: "LowCardinality(String)", default: "xcode"
    field :coverage_tool, Ch, type: "LowCardinality(String)", default: ""
    field :coverage_tool_version, Ch, type: "LowCardinality(String)", default: ""
    field :git_object_format, Ch, type: "LowCardinality(String)", default: ""
    field :scheme, Ch, type: "String", default: ""
    field :platform, Ch, type: "LowCardinality(String)", default: ""
    field :git_commit_sha, Ch, type: "String", default: ""
    field :covered_lines, Ch, type: "UInt64"
    field :executable_lines, Ch, type: "UInt64"
    field :partial, :boolean, default: false
    field :files, Ch, type: "UInt32", default: 0
    field :version, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :report_shards, Ch, type: "Array(UInt32)", default: []
    field :report_inserted_at, Ch, type: "Array(DateTime64(6))", default: []
  end
end
