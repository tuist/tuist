defmodule Tuist.Alerts.FlakyTestAlert do
  @moduledoc """
  Represents a triggered flaky test alert stored in the database.

  When a FlakyTestAlertRule's threshold is exceeded, a FlakyTestAlert is created
  to record the event. The flaky_test_alert_rule association provides access to
  all configuration and related entities (project, account) for notifications.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Alerts.FlakyTestAlertRule

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "flaky_test_alerts" do
    field :flaky_runs_count, :integer
    field :test_case_id, Ecto.UUID
    field :test_case_name, :string
    field :test_case_module_name, :string
    field :test_case_suite_name, :string

    belongs_to :flaky_test_alert_rule, FlakyTestAlertRule

    timestamps(type: :utc_datetime)
  end

  def changeset(flaky_test_alert \\ %__MODULE__{}, attrs) do
    flaky_test_alert
    |> cast(attrs, [
      :flaky_test_alert_rule_id,
      :flaky_runs_count,
      :test_case_id,
      :test_case_name,
      :test_case_module_name,
      :test_case_suite_name,
      :inserted_at
    ])
    |> validate_required([:flaky_test_alert_rule_id, :flaky_runs_count])
    |> foreign_key_constraint(:flaky_test_alert_rule_id)
  end
end
