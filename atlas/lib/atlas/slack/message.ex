defmodule Atlas.Slack.Message do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Event
  alias Atlas.Slack.Channel
  alias Atlas.Slack.User

  schema "slack_messages" do
    field :slack_ts, :string
    field :thread_ts, :string
    field :text, :string
    field :permalink, :string
    field :posted_at, :utc_datetime

    belongs_to :slack_channel, Channel
    belongs_to :slack_user, User
    belongs_to :account_event, Event

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:slack_ts, :thread_ts, :text, :permalink, :posted_at])
    |> validate_required([:slack_channel_id, :slack_ts, :posted_at])
    |> unique_constraint([:slack_channel_id, :slack_ts])
  end

  def top_level?(%__MODULE__{thread_ts: nil}), do: true
  def top_level?(%__MODULE__{thread_ts: thread_ts, slack_ts: ts}), do: thread_ts == ts
end
