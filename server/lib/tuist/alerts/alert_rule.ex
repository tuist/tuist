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

  @categories [build_run_duration: 0, test_run_duration: 1, cache_hit_rate: 2, bundle_size: 3]
  @metrics [p50: 0, p90: 1, p99: 2, average: 3, install_size: 4, download_size: 5]
  @environments [any: 0, ci: 1, local: 2]
  @bundle_size_metrics [:install_size, :download_size]
  @duration_metrics [:p50, :p90, :p99, :average]

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "alert_rules" do
    field :name, :string, default: "Untitled"
    field :category, Ecto.Enum, values: @categories
    field :metric, Ecto.Enum, values: @metrics
    field :deviation_percentage, :float
    field :rolling_window_size, :integer
    field :git_branch, :string
    field :slack_channel_id, :string
    field :slack_channel_name, :string
    field :scheme, :string, default: ""
    field :bundle_name, :string, default: ""
    field :environment, Ecto.Enum, values: @environments, default: :any

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
      :git_branch,
      :slack_channel_id,
      :slack_channel_name,
      :scheme,
      :bundle_name,
      :environment
    ])
    |> validate_required([
      :project_id,
      :name,
      :category,
      :metric,
      :deviation_percentage,
      :slack_channel_id,
      :slack_channel_name
    ])
    |> validate_number(:deviation_percentage, greater_than: 0)
    |> validate_category_fields()
    |> foreign_key_constraint(:project_id)
  end

  defp validate_category_fields(changeset) do
    category = get_field(changeset, :category)
    metric = get_field(changeset, :metric)

    changeset =
      case category do
        :bundle_size ->
          validate_required(changeset, [:git_branch])

        _ ->
          changeset
          |> validate_required([:rolling_window_size])
          |> validate_number(:rolling_window_size, greater_than: 0)
      end

    validate_metric_for_category(changeset, category, metric)
  end

  defp validate_metric_for_category(changeset, :bundle_size, metric) when not is_nil(metric) do
    if metric in @bundle_size_metrics do
      changeset
    else
      add_error(changeset, :metric, "is invalid for bundle_size category")
    end
  end

  defp validate_metric_for_category(changeset, category, metric)
       when category in [:build_run_duration, :test_run_duration, :cache_hit_rate] and not is_nil(metric) do
    if metric in @duration_metrics do
      changeset
    else
      add_error(changeset, :metric, "is invalid for #{category} category")
    end
  end

  defp validate_metric_for_category(changeset, _category, _metric), do: changeset

  def categories, do: @categories
  def metrics, do: @metrics
end
