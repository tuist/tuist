defmodule Atlas.Memory.Node do
  @moduledoc """
  A typed memory node curated by the Atlas Slack agent.

  Eight kinds map roughly to the spacebot.sh taxonomy: facts (objective info),
  preferences (likes/dislikes), decisions (a choice plus reasoning),
  identities (high-priority persona info), events (point-in-time occurrences),
  observations (system-detected patterns), goals (future objectives), and
  todos (actionable reminders). Each kind has a default importance used at
  insert time when the agent does not supply one.

  Scope is currently always `:global` for the company workspace, with
  `slack_channel_id` retained for future per-channel scoping.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Slack.Channel, as: SlackChannel
  alias Atlas.Slack.Message, as: SlackMessage
  alias Atlas.Slack.User, as: SlackUser

  @kinds [:fact, :preference, :decision, :identity, :event, :observation, :goal, :todo]
  @scopes [:global, :channel]
  @confirmations [:pending, :confirmed]

  @default_importance %{
    fact: 0.6,
    preference: 0.7,
    decision: 0.8,
    identity: 1.0,
    event: 0.4,
    observation: 0.3,
    goal: 0.9,
    todo: 0.8
  }

  schema "memory_nodes" do
    field :kind, Ecto.Enum, values: @kinds
    field :body, :string
    field :importance, :float, default: 0.5
    field :access_count, :integer, default: 0
    field :last_accessed_at, :utc_datetime
    field :forgotten, :boolean, default: false

    field :scope, Ecto.Enum, values: @scopes, default: :global
    field :slack_app, Ecto.Enum, values: [:company, :community]

    field :confirmation, Ecto.Enum, values: @confirmations, default: :confirmed
    field :proposal_slack_ts, :string

    field :embedding_model, :string
    field :embedded_at, :utc_datetime

    belongs_to :slack_channel, SlackChannel
    belongs_to :slack_user, SlackUser
    belongs_to :source_slack_message, SlackMessage

    timestamps()
  end

  @workflow_fields [:confirmation, :proposal_slack_ts]

  def kinds, do: @kinds
  def scopes, do: @scopes
  def confirmations, do: @confirmations
  def workflow_fields, do: @workflow_fields
  def default_importance(kind) when kind in @kinds, do: Map.fetch!(@default_importance, kind)

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :kind,
      :body,
      :importance,
      :scope,
      :slack_app,
      :forgotten
    ])
    |> validate_required([:kind, :body, :scope, :confirmation])
    |> validate_length(:body, min: 1, max: 4_000)
    |> validate_number(:importance, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> put_default_importance()
  end

  @doc """
  Internal changeset for proposal-lifecycle fields (`:confirmation`,
  `:proposal_slack_ts`). Kept separate from `changeset/2` so callers that
  hand in attribute maps from forms or LLM tool params cannot mass-assign
  workflow state — only `Atlas.Memory` should call this.
  """
  def workflow_changeset(node, attrs) do
    node
    |> cast(attrs, @workflow_fields)
  end

  @doc """
  Changeset for stamping the embedding model and timestamp after the
  embedding service has produced a vector. Kept separate from `changeset/2`
  so neither field can be set through the general attrs path.
  """
  def embedding_changeset(node, model, %DateTime{} = embedded_at) when is_binary(model) do
    node
    |> change()
    |> put_change(:embedding_model, model)
    |> put_change(:embedded_at, DateTime.truncate(embedded_at, :second))
  end

  defp put_default_importance(changeset) do
    cond do
      get_change(changeset, :importance) != nil ->
        changeset

      not is_nil(get_field(changeset, :id)) ->
        # Updating an existing row: leave the persisted importance alone.
        changeset

      true ->
        case get_field(changeset, :kind) do
          nil -> changeset
          kind -> put_change(changeset, :importance, default_importance(kind))
        end
    end
  end
end
