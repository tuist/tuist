defmodule Tuist.Automations.Alerts.Alert do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @monitor_types ~w(flakiness_rate flaky_run_count)
  @comparisons ~w(gte gt lt lte)
  @valid_states ~w(enabled muted skipped)

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "automation_alerts" do
    field :name, :string
    field :enabled, :boolean, default: true
    field :monitor_type, :string
    field :trigger_config, :map, default: %{}
    field :cadence, :string, default: "5m"
    field :trigger_actions, {:array, :map}, default: []
    field :recovery_enabled, :boolean, default: false
    field :recovery_config, :map, default: %{}
    field :recovery_actions, {:array, :map}, default: []
    field :baseline_established_at, :utc_datetime

    belongs_to :project, Project, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(alert \\ %__MODULE__{}, attrs) do
    alert
    |> cast(attrs, [
      :project_id,
      :name,
      :enabled,
      :monitor_type,
      :trigger_config,
      :cadence,
      :trigger_actions,
      :recovery_enabled,
      :recovery_config,
      :recovery_actions,
      :baseline_established_at
    ])
    |> validate_required([:project_id, :name, :monitor_type])
    |> validate_inclusion(:monitor_type, @monitor_types)
    |> validate_actions(:trigger_actions, require_present: true)
    |> validate_actions(:recovery_actions, require_present: false)
    |> validate_config()
    |> foreign_key_constraint(:project_id)
  end

  defp validate_actions(changeset, field, opts) do
    case get_field(changeset, field) do
      nil -> maybe_blank_error(changeset, field, opts)
      [] -> maybe_blank_error(changeset, field, opts)
      actions when is_list(actions) -> validate_action_list(changeset, field, actions)
      _ -> add_error(changeset, field, "must be a list")
    end
  end

  defp maybe_blank_error(changeset, field, opts) do
    if Keyword.get(opts, :require_present, false) do
      add_error(changeset, field, "can't be blank")
    else
      changeset
    end
  end

  defp validate_action_list(changeset, field, actions) do
    cond do
      not Enum.all?(actions, &valid_action?/1) ->
        add_error(changeset, field, "contains invalid actions")

      Enum.count(actions, &change_state_action?/1) > 1 ->
        add_error(changeset, field, "can only contain one change_state action")

      has_duplicate_label_action?(actions, "add_label") ->
        add_error(changeset, field, "can only contain one add_label action per label")

      has_duplicate_label_action?(actions, "remove_label") ->
        add_error(changeset, field, "can only contain one remove_label action per label")

      true ->
        changeset
    end
  end

  defp valid_action?(%{"type" => "change_state", "state" => state}) when state in @valid_states, do: true

  defp valid_action?(%{"type" => "send_slack", "channel" => channel, "message" => message})
       when is_binary(channel) and channel != "" and is_binary(message) and message != "", do: true

  defp valid_action?(%{"type" => "add_label", "label" => label}) when is_binary(label) and label != "", do: true
  defp valid_action?(%{"type" => "remove_label", "label" => label}) when is_binary(label) and label != "", do: true

  defp valid_action?(_), do: false

  defp change_state_action?(%{"type" => "change_state"}), do: true
  defp change_state_action?(_), do: false

  defp has_duplicate_label_action?(actions, type) do
    actions
    |> Enum.filter(fn a -> a["type"] == type end)
    |> Enum.map(fn a -> a["label"] end)
    |> then(fn labels -> length(labels) != length(Enum.uniq(labels)) end)
  end

  defp validate_config(changeset) do
    monitor_type = get_field(changeset, :monitor_type)
    trigger_config = get_field(changeset, :trigger_config) || %{}

    changeset =
      case monitor_type do
        "flakiness_rate" -> validate_flakiness_rate_config(changeset, trigger_config)
        "flaky_run_count" -> validate_flaky_run_count_config(changeset, trigger_config)
        _ -> changeset
      end

    validate_comparison(changeset, trigger_config)
  end

  defp validate_comparison(changeset, trigger_config) do
    case Map.get(trigger_config, "comparison") do
      nil -> changeset
      value when value in @comparisons -> changeset
      _ -> add_error(changeset, :trigger_config, "comparison must be one of: #{Enum.join(@comparisons, ", ")}")
    end
  end

  defp validate_flakiness_rate_config(changeset, trigger_config) do
    threshold = trigger_config["threshold"]
    window = trigger_config["window"]

    cond do
      !is_number(threshold) or threshold <= 0 or threshold > 100 ->
        add_error(changeset, :trigger_config, "threshold must be a number between 0 and 100")

      !is_binary(window) ->
        add_error(changeset, :trigger_config, "window must be a string like '30d'")

      true ->
        changeset
    end
  end

  defp validate_flaky_run_count_config(changeset, trigger_config) do
    threshold = trigger_config["threshold"]
    window = trigger_config["window"]

    cond do
      !is_integer(threshold) or threshold <= 0 ->
        add_error(changeset, :trigger_config, "threshold must be a positive integer")

      !is_binary(window) ->
        add_error(changeset, :trigger_config, "window must be a string like '30d'")

      true ->
        changeset
    end
  end
end
