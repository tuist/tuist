defmodule Tuist.Notifications.Rule do
  @moduledoc """
  A user's own notification rule: when `event` happens in one of the rule's
  projects, or in any project the user can subscribe to when it lists none,
  and the event meets `conditions`, run `actions`. `event` names a
  `Tuist.Notifications.Event` module, which validates the conditions; actions
  are validated by `Tuist.Notifications.Action`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.User
  alias Tuist.Notifications.Action
  alias Tuist.Notifications.Event
  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}

  schema "notification_rules" do
    belongs_to :user, User
    field :event, :string
    field :enabled, :boolean, default: true
    field :conditions, :map, default: %{}
    field :actions, {:array, :map}, default: []

    many_to_many :projects, Project,
      join_through: "notification_rule_projects",
      join_keys: [rule_id: :id, project_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Casts `attrs` (`event`, `enabled`, `conditions`, `actions`) and `projects`,
  already loaded and authorized by the caller.
  """
  def changeset(%__MODULE__{} = rule, attrs, projects) do
    rule
    |> cast(attrs, [:event, :enabled, :conditions, :actions])
    |> validate_required([:event, :enabled])
    |> validate_change(:event, fn :event, event ->
      if Event.get(event), do: [], else: [event: "is not a known notification event"]
    end)
    |> validate_conditions()
    |> validate_actions()
    |> put_assoc(:projects, projects)
  end

  defp validate_conditions(changeset) do
    with event when is_binary(event) <- get_field(changeset, :event),
         module when not is_nil(module) <- Event.get(event) do
      case module.cast_conditions(get_field(changeset, :conditions) || %{}) do
        {:ok, conditions} -> put_change(changeset, :conditions, conditions)
        {:error, message} -> add_error(changeset, :conditions, message)
      end
    else
      _ -> changeset
    end
  end

  defp validate_actions(changeset) do
    case Action.cast_all(get_field(changeset, :actions) || []) do
      {:ok, actions} -> put_change(changeset, :actions, actions)
      {:error, message} -> add_error(changeset, :actions, message)
    end
  end
end
