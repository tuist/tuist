defmodule Tuist.Automations.Alerts.Alert do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @monitor_types ~w(flakiness_rate flaky_run_count test_updated github_issue)
  @comparisons ~w(gte gt lt lte)
  @valid_states ~w(enabled muted skipped)
  @test_updated_events ~w(
    marked_flaky
    unmarked_flaky
    state_changed_to_enabled
    state_changed_to_muted
    state_changed_to_skipped
  )
  @github_issue_events ~w(closed)
  @window_types ~w(last_days rolling)

  # Cap on `rolling_window_size`. The monitor reads from
  # `test_case_runs_recent_per_case`, an AggregatingMergeTree MV whose
  # `groupArrayLast(N)` state is sized at this value, so raising the cap
  # without also bumping the MV's aggregate type would silently truncate
  # any window above the old N.
  @max_rolling_window_size 1000

  @doc """
  Subscription keys recognised on the `test_updated` monitor's
  `trigger_config["events"]` array. Stripe-style: subscribe by name, no
  threshold or content filter.
  """
  def test_updated_events, do: @test_updated_events

  @doc """
  Subscription keys recognised on the `github_issue` monitor's
  `trigger_config["events"]` array.
  """
  def github_issue_events, do: @github_issue_events

  @doc """
  Maximum value the `trigger_config.rolling_window_size` /
  `recovery_config.rolling_window_size` field accepts. Surfaced so the UI
  can apply the same constraint at the input level.
  """
  def max_rolling_window_size, do: @max_rolling_window_size

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

  defp valid_action?(%{"type" => "create_github_issue", "title_template" => title}) when is_binary(title) and title != "",
    do: true

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
        "test_updated" -> validate_test_updated_config(changeset, trigger_config)
        "github_issue" -> validate_github_issue_config(changeset, trigger_config)
        _ -> changeset
      end

    changeset
    |> validate_comparison(trigger_config)
    |> validate_recovery_config()
  end

  defp validate_test_updated_config(changeset, trigger_config) do
    validate_events_subscription(changeset, trigger_config, @test_updated_events)
  end

  defp validate_github_issue_config(changeset, trigger_config) do
    validate_events_subscription(changeset, trigger_config, @github_issue_events)
  end

  defp validate_events_subscription(changeset, trigger_config, allowed_events) do
    case Map.get(trigger_config, "events") do
      events when is_list(events) and events != [] ->
        invalid = Enum.reject(events, &(&1 in allowed_events))

        if invalid == [] do
          changeset
        else
          add_error(
            changeset,
            :trigger_config,
            "events contains invalid values: #{Enum.join(invalid, ", ")}"
          )
        end

      _ ->
        add_error(changeset, :trigger_config, "events must be a non-empty list")
    end
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

    if !is_number(threshold) or threshold <= 0 or threshold > 100 do
      add_error(changeset, :trigger_config, "threshold must be a number between 0 and 100")
    else
      validate_window_config(changeset, trigger_config)
    end
  end

  defp validate_flaky_run_count_config(changeset, trigger_config) do
    threshold = trigger_config["threshold"]

    if !is_integer(threshold) or threshold <= 0 do
      add_error(changeset, :trigger_config, "threshold must be a positive integer")
    else
      validate_window_config(changeset, trigger_config)
    end
  end

  # `window_type` selects between a calendar window ("last_days", configured
  # via `window: "30d"`) and a count-based rolling window ("rolling",
  # configured via `rolling_window_size: 100`). Every persisted row carries an
  # explicit `window_type` after the backfill migration, so missing values are
  # rejected here instead of inferred.
  defp validate_window_config(changeset, trigger_config) do
    case validate_window_shape(trigger_config) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :trigger_config, message)
    end
  end

  # Recovery is only validated when the user opts in. The shape mirrors
  # `trigger_config` so a `rolling_window_size: 0` can't sneak past and have
  # the worker silently fall back to its default.
  defp validate_recovery_config(changeset) do
    if get_field(changeset, :recovery_enabled) do
      recovery_config = get_field(changeset, :recovery_config) || %{}

      case validate_window_shape(recovery_config) do
        :ok -> changeset
        {:error, message} -> add_error(changeset, :recovery_config, message)
      end
    else
      changeset
    end
  end

  defp validate_window_shape(config) do
    case window_type(config) do
      "last_days" ->
        if valid_window?(config["window"]),
          do: :ok,
          else: {:error, "window must be a string like '30d' (day-level only)"}

      "rolling" ->
        size = config["rolling_window_size"]

        cond do
          not (is_integer(size) and size > 0) ->
            {:error, "rolling_window_size must be a positive integer"}

          size > @max_rolling_window_size ->
            {:error, "rolling_window_size must be at most #{@max_rolling_window_size}"}

          true ->
            :ok
        end

      _ ->
        {:error, "window_type must be one of: #{Enum.join(@window_types, ", ")}"}
    end
  end

  defp window_type(%{"window_type" => type}) when type in @window_types, do: type
  defp window_type(_), do: :invalid

  # The flaky-test monitor evaluates against a per-day-aggregated MV, so
  # sub-day windows would silently round to a full day and look broken.
  # Constrain `trigger_config.window` to day-level (`Nd`) up front so users
  # don't think `1h` / `5m` are honored.
  defp valid_window?(window) when is_binary(window), do: Regex.match?(~r/^[1-9]\d*d$/, window)
  defp valid_window?(_), do: false
end
