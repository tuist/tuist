defmodule Tuist.Runs.TestCaseEvent do
  @moduledoc """
  Represents an audit event for a test case.

  Events track state changes like:
  - marked_flaky / unmarked_flaky
  - quarantined / unquarantined

  Each event records who performed the action (user or system) and optionally why.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Projects.Project

  @derive {
    Flop.Schema,
    filterable: [:test_case_id, :event_type],
    sortable: [:inserted_at, :id],
    default_order: %{
      order_by: [:inserted_at, :id],
      order_directions: [:desc, :desc]
    },
    default_limit: 20,
    max_limit: 100
  }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "test_case_events" do
    field :test_case_id, Ecto.UUID
    field :event_type, Ecto.Enum, values: [:marked_flaky, :unmarked_flaky, :quarantined, :unquarantined]
    field :actor_type, Ecto.Enum, values: [:user, :system]
    field :reason, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Project
    belongs_to :actor, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:test_case_id, :project_id, :event_type, :actor_type, :actor_id, :reason, :metadata])
    |> validate_required([:test_case_id, :project_id, :event_type, :actor_type])
    |> validate_actor()
  end

  defp validate_actor(changeset) do
    actor_type = get_field(changeset, :actor_type)
    actor_id = get_field(changeset, :actor_id)

    case {actor_type, actor_id} do
      {:user, nil} ->
        add_error(changeset, :actor_id, "is required when actor_type is user")

      {:system, id} when not is_nil(id) ->
        add_error(changeset, :actor_id, "must be nil when actor_type is system")

      _ ->
        changeset
    end
  end
end
