defmodule Tuist.Tests.FlakyTestCaseRun do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "flaky_test_case_runs" do
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
