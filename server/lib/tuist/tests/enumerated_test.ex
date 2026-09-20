defmodule Tuist.Tests.EnumeratedTest do
  @moduledoc """
  A test a run could have executed, listed by the client without running it.
  `test_case_id` is the test case's stable id
  (`Tuist.Tests.generate_test_case_id/4`), shared with `test_case_runs`.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_run_enumerated_tests" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :test_case_id, Ecto.UUID
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String", default: ""
    field :name, Ch, type: "String"
    field :enabled, :boolean, default: true
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
