defmodule Tuist.Alerts.FlakyTestAlertRule do
  @moduledoc """
  Represents a flaky test alert rule configuration for a project.

  Flaky test alert rules define when alerts should be triggered based on the number
  of test runs with flaky tests.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Alerts.FlakyTestAlert
  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "flaky_test_alert_rules" do
    field :name, :string, default: "Untitled"
    field :trigger_threshold, :integer
    field :slack_channel_id, :string
    field :slack_channel_name, :string

    belongs_to :project, Project, type: :integer
    has_many :flaky_test_alerts, FlakyTestAlert

    timestamps(type: :utc_datetime)
  end

  def changeset(flaky_test_alert_rule \\ %__MODULE__{}, attrs) do
    flaky_test_alert_rule
    |> cast(attrs, [
      :project_id,
      :name,
      :trigger_threshold,
      :slack_channel_id,
      :slack_channel_name
    ])
    |> validate_required([
      :project_id,
      :name,
      :trigger_threshold,
      :slack_channel_id,
      :slack_channel_name
    ])
    |> validate_number(:trigger_threshold, greater_than: 0)
    |> foreign_key_constraint(:project_id)
  end
end
