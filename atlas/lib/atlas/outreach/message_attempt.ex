defmodule Atlas.Outreach.MessageAttempt do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.Recommendation

  @message_kinds ~w(inmail message reply follow_up manual)
  @message_intents ~w(understand_problem deepen_context offer_help propose_evaluation)
  @personalization_sources ~w(recipient_message public_work account_signal role_context)
  @calls_to_action ~w(question resource_offer meeting none)
  @outcomes ~w(pending replied positive_reply objection not_interested no_reply)
  @response_outcomes ~w(replied positive_reply objection not_interested)

  schema "outreach_message_attempts" do
    field :channel, :string, default: "linkedin"
    field :message_kind, :string
    field :message_intent, :string
    field :personalization_source, :string
    field :call_to_action, :string
    field :proposed_subject, :string
    field :proposed_message, :string
    field :sent_subject, :string
    field :sent_message, :string
    field :outcome, :string, default: "pending"
    field :sent_at, :utc_datetime
    field :outcome_at, :utc_datetime

    belongs_to :contact, Contact
    belongs_to :account, Account
    belongs_to :recommendation, Recommendation
    belongs_to :sent_event, Event
    belongs_to :response_event, Event

    timestamps()
  end

  def message_kinds, do: @message_kinds
  def message_intents, do: @message_intents
  def personalization_sources, do: @personalization_sources
  def calls_to_action, do: @calls_to_action
  def outcomes, do: @outcomes
  def response_outcomes, do: @response_outcomes

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :channel,
      :message_kind,
      :message_intent,
      :personalization_source,
      :call_to_action,
      :proposed_subject,
      :proposed_message,
      :sent_subject,
      :sent_message,
      :outcome,
      :sent_at
    ])
    |> normalize_strings()
    |> validate_required([
      :contact_id,
      :account_id,
      :sent_event_id,
      :channel,
      :message_kind,
      :sent_message,
      :outcome,
      :sent_at
    ])
    |> validate_inclusion(:channel, ["linkedin"])
    |> validate_inclusion(:message_kind, @message_kinds)
    |> validate_optional_inclusion(:message_intent, @message_intents)
    |> validate_optional_inclusion(:personalization_source, @personalization_sources)
    |> validate_optional_inclusion(:call_to_action, @calls_to_action)
    |> validate_inclusion(:outcome, @outcomes)
    |> validate_length(:proposed_subject, max: 120)
    |> validate_length(:proposed_message, max: 1_500)
    |> validate_length(:sent_subject, max: 120)
    |> validate_length(:sent_message, max: 1_500)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:recommendation_id)
    |> foreign_key_constraint(:sent_event_id)
    |> unique_constraint(:sent_event_id)
    |> check_constraint(:channel, name: :outreach_message_attempts_channel_check)
    |> check_constraint(:message_kind, name: :outreach_message_attempts_kind_check)
    |> check_constraint(:message_intent, name: :outreach_message_attempts_intent_check)
    |> check_constraint(:personalization_source,
      name: :outreach_message_attempts_personalization_source_check
    )
    |> check_constraint(:call_to_action, name: :outreach_message_attempts_call_to_action_check)
    |> check_constraint(:outcome, name: :outreach_message_attempts_outcome_check)
  end

  def outcome_changeset(attempt, attrs) do
    attempt
    |> change(Map.take(attrs, [:outcome, :outcome_at, :response_event_id]))
    |> validate_required([:outcome, :outcome_at, :response_event_id])
    |> validate_inclusion(:outcome, @response_outcomes)
    |> foreign_key_constraint(:response_event_id)
    |> unique_constraint(:response_event_id)
    |> check_constraint(:outcome, name: :outreach_message_attempts_outcome_check)
  end

  defp validate_optional_inclusion(changeset, field, values) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_inclusion(changeset, field, values)
    end
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [
        :channel,
        :message_kind,
        :message_intent,
        :personalization_source,
        :call_to_action,
        :proposed_subject,
        :proposed_message,
        :sent_subject,
        :sent_message,
        :outcome
      ],
      changeset,
      fn field, changeset ->
        update_change(changeset, field, fn
          nil -> nil
          value when is_binary(value) -> value |> String.trim() |> empty_to_nil()
          value -> value
        end)
      end
    )
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
