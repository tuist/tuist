defmodule Tuist.Tests.CoverageTestSource do
  @moduledoc """
  A version of a test, by the fingerprint of the files it executed, and the
  latest run that recorded it (`Tuist.Tests.Coverage.TestSources`).
  """
  use Ecto.Schema

  @primary_key false
  schema "coverage_test_sources" do
    field :project_id, Ch, type: "Int64"
    field :git_repository_id, Ch, type: "Int64"
    field :test_case_id, Ch, type: "UUID"
    field :fingerprint, Ch, type: "String"
    field :paths, Ch, type: "Array(String)"
    field :unlined_paths, Ch, type: "Array(String)"
    field :passed, Ch, type: "Bool"
    field :test_run_id, Ch, type: "UUID"
    field :git_commit_sha, Ch, type: "String"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
