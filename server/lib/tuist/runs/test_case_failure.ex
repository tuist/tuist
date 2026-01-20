defmodule Tuist.Runs.TestCaseFailure do
  @moduledoc """
  A test case failure represents a single failure within a test case run.
  This is a ClickHouse entity that stores test case failure data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :test_case_run_id,
      :path,
      :issue_type
    ],
    sortable: [:inserted_at]
  }

  def valid_types do
    [
      "error_thrown",
      "assertion_failure",
      "issue_recorded",
      "unknown"
    ]
  end

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_failures" do
    field :test_case_run_id, Ecto.UUID
    field :message, :string
    field :path, :string
    field :line_number, Ch, type: "Int32"
    field :issue_type, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(test_case_failure, attrs) do
    test_case_failure
    |> cast(
      %{
        id: attrs[:id],
        test_case_run_id: attrs[:test_case_run_id],
        message: attrs[:message],
        path: attrs[:path],
        line_number: attrs[:line_number],
        issue_type: attrs[:issue_type] || "unknown",
        inserted_at: attrs[:inserted_at]
      },
      [
        :id,
        :test_case_run_id,
        :message,
        :path,
        :line_number,
        :issue_type,
        :inserted_at
      ]
    )
    |> validate_required([
      :id,
      :test_case_run_id,
      :line_number,
      :issue_type
    ])
    |> validate_inclusion(:issue_type, valid_types())
  end
end
