defmodule Atlas.Nudges.SlackPostAttempt do
  @moduledoc """
  Durable record of one nudge's Slack posting attempts. Carries a
  client-generated id sent to Slack in the message metadata so a retry after
  an ambiguous failure can reconcile via `Atlas.Slack.API.find_message_by_metadata/4`
  before re-posting.

  Bounded duplicate risk exists past Slack's 100-message reconciliation
  window; the follow-up PR that adds email sending also replaces this with a
  provider-side dedup mechanism.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Nudges.Nudge

  @states ~w(pending posted failed)

  schema "nudge_slack_post_attempts" do
    field :client_msg_id, :string
    field :channel_id, :string
    field :message_ts, :string
    field :state, :string, default: "pending"
    field :last_error, :string
    field :attempts, :integer, default: 0

    belongs_to :nudge, Nudge

    timestamps()
  end

  def states, do: @states

  def create_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [:nudge_id, :client_msg_id, :channel_id])
    |> put_change(:state, "pending")
    |> put_change(:attempts, 0)
    |> validate_required([:nudge_id, :client_msg_id, :channel_id])
    |> unique_constraint(:client_msg_id)
    |> foreign_key_constraint(:nudge_id)
    |> check_constraint(:state, name: :nudge_slack_post_attempts_state_check)
  end

  def posted_changeset(attempt, message_ts) when is_binary(message_ts) do
    attempt
    |> change(%{state: "posted", message_ts: message_ts, last_error: nil})
    |> increment_attempts()
  end

  def failed_changeset(attempt, error) do
    attempt
    |> change(%{state: "failed", last_error: inspect(error)})
    |> increment_attempts()
  end

  defp increment_attempts(changeset) do
    current = get_field(changeset, :attempts) || 0
    put_change(changeset, :attempts, current + 1)
  end
end
