defmodule Tuist.Tests.CoverageCommit do
  @moduledoc """
  A commit's line coverage within a project: the union of every run that
  measured the commit (a line is covered when any run covered it; a file
  counts once however many schemes compiled it), with the **measured set**
  that produced it: the schemes that ran (`schemes`), those of them that
  only ran partially (`partial_schemes`) and the runs themselves.

  `complete` says the commit's coverage pipeline is known to have finished,
  and `completeness` how that was established: `signal` when the client said
  so (`Tuist.Tests.Coverage.Commits.signal_complete/3`), `inferred` when the
  measured set matches the previous chained commit's. `unmeasured_files_count`
  is how many source files of the commit's listing no run measured.

  Every run that reports coverage for the commit, and the signal, republish
  the row one version above the latest, as `Tuist.Tests.CoverageRun` does; a
  run from a dirty checkout never contributes.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_commits" do
    field :project_id, Ch, type: "Int64"
    field :git_commit_sha, Ch, type: "String"
    field :git_repository_id, Ch, type: "Int64", default: 0
    field :build_system, Ch, type: "LowCardinality(String)", default: "xcode"
    field :covered_lines, Ch, type: "UInt64"
    field :executable_lines, Ch, type: "UInt64"
    field :measured_files_count, Ch, type: "UInt32", default: 0
    field :unmeasured_files_count, Ch, type: "UInt32", default: 0
    field :schemes, Ch, type: "Array(String)", default: []
    field :partial_schemes, Ch, type: "Array(String)", default: []
    field :test_run_ids, {:array, Ecto.UUID}, default: []
    field :complete, :boolean, default: false
    field :completeness, Ch, type: "LowCardinality(String)", default: ""
    field :reported_covered_lines, Ch, type: "UInt64", default: 0
    field :reported_executable_lines, Ch, type: "UInt64", default: 0
    field :reported_kind, Ch, type: "LowCardinality(String)", default: ""
    field :skipped_tests_count, Ch, type: "UInt32", default: 0
    field :carried_tests_count, Ch, type: "UInt32", default: 0
    field :gap_files_count, Ch, type: "UInt32", default: 0
    field :carried_from, Ch, type: "Array(String)", default: []
    field :version, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
