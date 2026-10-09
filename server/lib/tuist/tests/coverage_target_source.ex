defmodule Tuist.Tests.CoverageTargetSource do
  @moduledoc """
  A clean run that executed a test target whole, passed it and recorded its
  evidence, by the selective-testing hash the target ran with
  (`Tuist.Tests.Coverage.TargetSources`).
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_target_sources" do
    field :project_id, Ch, type: "Int64"
    field :target, Ch, type: "String"
    field :selective_testing_hash, Ch, type: "String"
    field :test_run_id, Ch, type: "UUID"
    field :git_commit_sha, Ch, type: "String"
    field :git_repository_id, Ch, type: "Int64"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
