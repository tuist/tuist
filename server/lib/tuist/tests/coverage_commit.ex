defmodule Tuist.Tests.CoverageCommit do
  @moduledoc """
  A commit's line coverage within a project: the union of every run that
  measured the commit (a line is covered when any run covered it; a file
  counts once however many schemes compiled it), with the **measured set**
  that produced it: the schemes that ran (`schemes`), those of them that
  only ran partially (`partial_schemes`) and the runs themselves.

  `complete` says the commit's coverage pipeline is known to have finished,
  and `completeness` how that was established: `signal` when the client said
  so (`Tuist.Tests.Coverage.Commits.signal_complete/2`), `inferred` when the
  measured set matches the previous chained commit's. `unmeasured_files_count`
  is how many source files of the commit's listing no run measured.

  The row sits beside the commit graph: `ref_id`, `position` and
  `committed_at` copy the commit's place in it (`Tuist.GitHistory.Ref`), so a
  branch's coverage is a range over its positions and outlives the graph's
  window. `git_branch`, `pull_request_number`, `base_branch` and `ran_at` are
  what the commit's runs reported. Every fold rewrites the row and bumps
  `version`; a run from a dirty checkout never contributes.
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_commits" do
    field :project_id, :integer, primary_key: true
    field :git_commit_sha, :string, primary_key: true
    field :repository_id, :integer
    field :ref_id, :integer
    field :position, :integer
    field :committed_at, :utc_datetime_usec
    field :build_system, :string, default: "xcode"
    field :git_branch, :string, default: ""
    field :pull_request_number, :integer, default: 0
    field :base_branch, :string, default: ""
    field :ran_at, :utc_datetime_usec
    field :covered_lines, :integer, default: 0
    field :executable_lines, :integer, default: 0
    field :measured_files_count, :integer, default: 0
    field :unmeasured_files_count, :integer, default: 0
    field :schemes, {:array, :string}, default: []
    field :partial_schemes, {:array, :string}, default: []
    field :test_run_ids, {:array, Ecto.UUID}, default: []
    field :complete, :boolean, default: false
    field :completeness, :string, default: ""
    field :reported_covered_lines, :integer, default: 0
    field :reported_executable_lines, :integer, default: 0
    field :reported_kind, :string, default: ""
    field :skipped_tests_count, :integer, default: 0
    field :carried_tests_count, :integer, default: 0
    field :gap_files_count, :integer, default: 0
    field :carried_from, {:array, :string}, default: []
    field :version, :integer, default: 1
    timestamps(type: :utc_datetime)
  end
end
