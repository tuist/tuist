defmodule Tuist.Alerts.AlertRule do
  @moduledoc """
  Represents an alert rule configuration for a project.

  Alert rules define when alerts should be triggered based on metric regressions.
  Each rule has a 24-hour cooldown to prevent notification spam.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Alerts.Alert
  alias Tuist.Projects.Project

  @categories [build_run_duration: 0, test_run_duration: 1, cache_hit_rate: 2]
  @metrics [p50: 0, p90: 1, p99: 2, average: 3]

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "alert_rules" do
    field :name, :string, default: "Untitled"
    field :category, Ecto.Enum, values: @categories
    field :metric, Ecto.Enum, values: @metrics
    field :deviation_percentage, :float
    field :rolling_window_size, :integer
    field :slack_channel_id, :string
    field :slack_channel_name, :string

    belongs_to :project, Project, type: :integer
    has_many :alerts, Alert

    timestamps(type: :utc_datetime)
  end

  def changeset(alert_rule \\ %__MODULE__{}, attrs) do
    alert_rule
    |> cast(attrs, [
      :project_id,
      :name,
      :category,
      :metric,
      :deviation_percentage,
      :rolling_window_size,
      :slack_channel_id,
      :slack_channel_name
    ])
    |> validate_required([
      :project_id,
      :name,
      :category,
      :metric,
      :deviation_percentage,
      :rolling_window_size,
      :slack_channel_id,
      :slack_channel_name
    ])
    |> validate_number(:deviation_percentage, greater_than: 0)
    |> validate_number(:rolling_window_size, greater_than: 0)
    |> foreign_key_constraint(:project_id)
  end

  def categories, do: @categories
  def metrics, do: @metrics
end
