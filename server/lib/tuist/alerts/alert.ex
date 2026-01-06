defmodule Tuist.Alerts.Alert do
  @moduledoc """
  Represents a triggered alert stored in the database.

  When an AlertRule's threshold is exceeded, an Alert is created to record
  the event. The alert_rule association provides access to all configuration
  and related entities (project, account) for notifications.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Alerts.AlertRule

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "alerts" do
    field :current_value, :float
    field :previous_value, :float

    belongs_to :alert_rule, AlertRule

    timestamps(type: :utc_datetime)
  end

  def changeset(alert \\ %__MODULE__{}, attrs) do
    alert
    |> cast(attrs, [:alert_rule_id, :current_value, :previous_value])
    |> validate_required([:alert_rule_id, :current_value, :previous_value])
    |> foreign_key_constraint(:alert_rule_id)
  end

  @doc """
  Computes the change percentage based on current/previous values and category.

  For increase regressions (build_run_duration, test_run_duration):
    change = (current - previous) / previous * 100

  For decrease regressions (cache_hit_rate):
    change = (previous - current) / previous * 100
  """
  def change_percentage(%__MODULE__{alert_rule: %{category: category}} = alert)
      when category in [:build_run_duration, :test_run_duration] do
    Float.round((alert.current_value - alert.previous_value) / alert.previous_value * 100, 1)
  end

  def change_percentage(%__MODULE__{alert_rule: %{category: :cache_hit_rate}} = alert) do
    Float.round((alert.previous_value - alert.current_value) / alert.previous_value * 100, 1)
  end
end
