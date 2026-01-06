defmodule Tuist.Alerts.AlertRule do
  @moduledoc """
  Represents an alert rule configuration for a project.

  Alert rules define when alerts should be triggered based on metric regressions.
  Each rule has a 24-hour cooldown to prevent notification spam.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @categories [build_run_duration: 0, test_run_duration: 1, cache_hit_rate: 2]
  @metrics [p50: 0, p90: 1, p99: 2, average: 3]

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "alert_rules" do
    field :category, Ecto.Enum, values: @categories
    field :metric, Ecto.Enum, values: @metrics
    field :threshold_percentage, :float
    field :sample_size, :integer
    field :enabled, :boolean, default: true
    field :slack_channel_id, :string
    field :slack_channel_name, :string
    field :last_triggered_at, :utc_datetime

    belongs_to :project, Project, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(alert_rule \\ %__MODULE__{}, attrs) do
    alert_rule
    |> cast(attrs, [
      :project_id,
      :category,
      :metric,
      :threshold_percentage,
      :sample_size,
      :enabled,
      :slack_channel_id,
      :slack_channel_name,
      :last_triggered_at
    ])
    |> validate_required([
      :project_id,
      :category,
      :metric,
      :threshold_percentage,
      :sample_size,
      :slack_channel_id,
      :slack_channel_name
    ])
    |> validate_number(:threshold_percentage, greater_than: 0)
    |> validate_number(:sample_size, greater_than: 0, less_than_or_equal_to: 1000)
    |> foreign_key_constraint(:project_id)
  end

  def categories, do: @categories
  def metrics, do: @metrics
end
