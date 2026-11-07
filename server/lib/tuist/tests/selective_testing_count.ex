defmodule Tuist.Tests.SelectiveTestingCount do
  @moduledoc """
  The tests an Xcode test run with selective testing was asked for and the
  ones selective testing skipped (`Tuist.Tests.SelectiveTestingCounts`).
  """
  use Ecto.Schema

  @primary_key false
  schema "test_run_selective_testing_counts" do
    field :test_run_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :is_ci, :boolean
    field :scheme, Ch, type: "String"
    field :requested_test_count, Ch, type: "UInt32"
    field :skipped_test_count, Ch, type: "UInt32"
    field :skipped_module_count, Ch, type: "UInt32"
    field :skipped_modules_without_history, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
