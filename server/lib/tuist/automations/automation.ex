defmodule Tuist.Automations.Automation do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @automation_types ~w(flakiness_rate flaky_run_count)
  @action_types ~w(change_state send_slack mark_as_flaky unmark_as_flaky)
  @valid_states ~w(enabled muted)

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "automations" do
    field :name, :string
    field :enabled, :boolean, default: true
    field :automation_type, :string
    field :config, :map, default: %{}
    field :cadence, :string, default: "5m"
    field :trigger_actions, {:array, :map}, default: []
    field :recovery_enabled, :boolean, default: false
    field :recovery_config, :map, default: %{}
    field :recovery_actions, {:array, :map}, default: []

    belongs_to :project, Project, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(automation \\ %__MODULE__{}, attrs) do
    automation
    |> cast(attrs, [
      :project_id,
      :name,
      :enabled,
      :automation_type,
      :config,
      :cadence,
      :trigger_actions,
      :recovery_enabled,
      :recovery_config,
      :recovery_actions
    ])
    |> validate_required([:project_id, :name, :automation_type])
    |> validate_inclusion(:automation_type, @automation_types)
    |> validate_actions(:trigger_actions, require_present: true)
    |> validate_actions(:recovery_actions, require_present: false)
    |> validate_config()
    |> foreign_key_constraint(:project_id)
  end

  defp validate_actions(changeset, field, opts) do
    require_present = Keyword.get(opts, :require_present, false)

    case get_field(changeset, field) do
      nil ->
        if require_present, do: add_error(changeset, field, "can't be blank"), else: changeset

      [] ->
        if require_present, do: add_error(changeset, field, "can't be blank"), else: changeset

      actions when is_list(actions) ->
        cond do
          not Enum.all?(actions, &valid_action?/1) ->
            add_error(changeset, field, "contains invalid actions")

          Enum.count(actions, &change_state_action?/1) > 1 ->
            add_error(changeset, field, "can only contain one change_state action")

          Enum.count(actions, &mark_as_flaky_action?/1) > 1 ->
            add_error(changeset, field, "can only contain one mark_as_flaky action")

          Enum.count(actions, &unmark_as_flaky_action?/1) > 1 ->
            add_error(changeset, field, "can only contain one unmark_as_flaky action")

          true ->
            changeset
        end

      _ ->
        add_error(changeset, field, "must be a list")
    end
  end

  defp valid_action?(%{"type" => "change_state", "state" => state}) when state in @valid_states, do: true

  defp valid_action?(%{"type" => "send_slack", "channel" => channel, "message" => message})
       when is_binary(channel) and channel != "" and is_binary(message) and message != "",
       do: true

  defp valid_action?(%{"type" => "mark_as_flaky"}), do: true
  defp valid_action?(%{"type" => "unmark_as_flaky"}), do: true

  defp valid_action?(_), do: false

  defp change_state_action?(%{"type" => "change_state"}), do: true
  defp change_state_action?(_), do: false

  defp mark_as_flaky_action?(%{"type" => "mark_as_flaky"}), do: true
  defp mark_as_flaky_action?(_), do: false

  defp unmark_as_flaky_action?(%{"type" => "unmark_as_flaky"}), do: true
  defp unmark_as_flaky_action?(_), do: false

  defp validate_config(changeset) do
    automation_type = get_field(changeset, :automation_type)
    config = get_field(changeset, :config) || %{}

    case automation_type do
      "flakiness_rate" ->
        validate_flakiness_rate_config(changeset, config)

      "flaky_run_count" ->
        validate_flaky_run_count_config(changeset, config)

      _ ->
        changeset
    end
  end

  defp validate_flakiness_rate_config(changeset, config) do
    threshold = config["threshold"]
    window = config["window"]

    cond do
      !is_number(threshold) or threshold <= 0 or threshold > 100 ->
        add_error(changeset, :config, "threshold must be a number between 0 and 100")

      !is_binary(window) ->
        add_error(changeset, :config, "window must be a string like '30d'")

      true ->
        changeset
    end
  end

  defp validate_flaky_run_count_config(changeset, config) do
    threshold = config["threshold"]
    window = config["window"]

    cond do
      !is_integer(threshold) or threshold <= 0 ->
        add_error(changeset, :config, "threshold must be a positive integer")

      !is_binary(window) ->
        add_error(changeset, :config, "window must be a string like '30d'")

      true ->
        changeset
    end
  end

  def automation_types, do: @automation_types
  def action_types, do: @action_types
end
