defmodule Atlas.Nudges.Nudge do
  @moduledoc """
  A proposed outbound to an account, produced by a signal and posted as a
  Slack card for a human to claim, act on, or dismiss.

  V1 does not send the email from Atlas; the operator claims the card and
  sends the drafted message themselves. Later versions add a `sent` state
  and durable Gmail delivery.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Users.User

  @states ~w(pending_post proposed claimed dismissed expired)
  @open_states ~w(pending_post proposed claimed)
  @severities ~w(low normal high)

  schema "account_nudges" do
    field :signal, :string
    field :dedup_key, :string
    field :state, :string, default: "pending_post"
    field :severity, :string, default: "normal"

    field :title, :string
    field :rationale, :string
    field :evidence, :map, default: %{}

    field :draft_subject, :string
    field :draft_body, :string

    field :claimed_at, :utc_datetime
    field :dismissed_at, :utc_datetime
    field :dismissed_reason, :string
    field :dismissed_until, :utc_datetime
    field :expired_at, :utc_datetime

    field :slack_channel_id, :string
    field :slack_message_ts, :string

    field :expires_at, :utc_datetime

    belongs_to :account, Account
    belongs_to :contact, Contact
    belongs_to :claimed_by_user, User, foreign_key: :claimed_by_user_id

    timestamps()
  end

  def states, do: @states
  def open_states, do: @open_states
  def severities, do: @severities

  def create_changeset(nudge, attrs) do
    nudge
    |> cast(attrs, [
      :account_id,
      :contact_id,
      :signal,
      :dedup_key,
      :severity,
      :title,
      :rationale,
      :evidence,
      :draft_subject,
      :draft_body,
      :expires_at
    ])
    |> put_change(:state, "pending_post")
    |> normalize_strings([:signal, :dedup_key, :title, :draft_subject])
    |> validate_required([
      :account_id,
      :signal,
      :dedup_key,
      :title,
      :rationale,
      :draft_subject,
      :draft_body,
      :expires_at
    ])
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:contact_id)
    |> unique_constraint([:account_id, :dedup_key],
      name: :account_nudges_open_dedup_index
    )
    |> check_constraint(:state, name: :account_nudges_state_check)
    |> check_constraint(:severity, name: :account_nudges_severity_check)
  end

  def mark_posted_changeset(%__MODULE__{state: "pending_post"} = nudge, attrs) do
    nudge
    |> cast(attrs, [:slack_channel_id, :slack_message_ts])
    |> put_change(:state, "proposed")
    |> validate_required([:slack_channel_id, :slack_message_ts])
  end

  def mark_posted_changeset(nudge, _attrs) do
    nudge |> change() |> add_error(:state, "must be pending_post to mark posted")
  end

  def claim_changeset(%__MODULE__{state: state} = nudge, %User{} = actor) when state in ["proposed", "claimed"] do
    nudge
    |> change(%{
      state: "claimed",
      claimed_by_user_id: actor.id,
      claimed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def claim_changeset(nudge, _actor) do
    nudge |> change() |> add_error(:state, "must be proposed to claim")
  end

  def release_changeset(%__MODULE__{state: "claimed"} = nudge) do
    nudge
    |> change(%{state: "proposed", claimed_by_user_id: nil, claimed_at: nil})
  end

  def release_changeset(nudge) do
    nudge |> change() |> add_error(:state, "must be claimed to release")
  end

  def dismiss_changeset(%__MODULE__{state: state} = nudge, attrs) when state in ["proposed", "claimed"] do
    nudge
    |> cast(attrs, [:dismissed_reason, :dismissed_until])
    |> put_change(:state, "dismissed")
    |> put_change(:dismissed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> normalize_strings([:dismissed_reason])
    |> validate_required([:dismissed_reason])
    |> check_constraint(:dismissed_reason,
      name: :account_nudges_dismissed_reason_check
    )
  end

  def dismiss_changeset(nudge, _attrs) do
    nudge |> change() |> add_error(:state, "must be open to dismiss")
  end

  def expire_changeset(%__MODULE__{state: state} = nudge) when state in ["pending_post", "proposed", "claimed"] do
    nudge
    |> change(%{
      state: "expired",
      expired_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def expire_changeset(nudge) do
    nudge |> change() |> add_error(:state, "must be open to expire")
  end

  defp normalize_strings(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      update_change(cs, field, fn
        nil -> nil
        value when is_binary(value) -> value |> String.trim() |> nil_if_empty()
        value -> value
      end)
    end)
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value
end
