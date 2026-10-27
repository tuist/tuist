defmodule Atlas.Outreach.Recommendation do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Users.User

  @statuses ~w(pending completed dismissed superseded)
  @action_types ~w(research wait engage connection_request inmail message reply follow_up nurture stop)
  @event_kinds ~w(connection_requested message_sent note)

  schema "outreach_recommendations" do
    field :status, :string, default: "pending"
    field :action_type, :string
    field :recommended_event_kind, :string
    field :title, :string
    field :guidance, :string
    field :rationale, :string
    field :draft_subject, :string
    field :draft_message, :string
    field :due_at, :utc_datetime
    field :confidence, :decimal
    field :evidence, :map, default: %{"items" => []}
    field :generated_by_agent, :string
    field :reviewed_at, :utc_datetime
    field :review_reason, :string
    field :slack_notification_requested_at, :utc_datetime
    field :slack_notification_posted_at, :utc_datetime
    field :slack_notification_channel_id, :string
    field :slack_notification_thread_ts, :string
    field :metadata, :map, default: %{}

    belongs_to :contact, Contact
    belongs_to :account, Account
    belongs_to :source_event, Event
    belongs_to :reviewed_by, User
    has_one :message_attempt, MessageAttempt

    timestamps()
  end

  def statuses, do: @statuses
  def action_types, do: @action_types
  def event_kinds, do: @event_kinds

  def changeset(recommendation, attrs) do
    recommendation
    |> cast(attrs, [
      :status,
      :action_type,
      :recommended_event_kind,
      :title,
      :guidance,
      :rationale,
      :draft_subject,
      :draft_message,
      :due_at,
      :confidence,
      :evidence,
      :generated_by_agent,
      :metadata
    ])
    |> normalize_strings()
    |> validate_required([
      :contact_id,
      :account_id,
      :status,
      :action_type,
      :title,
      :guidance,
      :rationale,
      :due_at,
      :confidence,
      :generated_by_agent
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:action_type, @action_types)
    |> validate_optional_inclusion(:recommended_event_kind, @event_kinds)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_length(:draft_subject, max: 120)
    |> validate_length(:draft_message, max: 1_500)
    |> validate_channel_draft()
    |> validate_evidence()
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:source_event_id)
    |> unique_constraint(:contact_id, name: :outreach_recommendations_pending_contact_index)
    |> check_constraint(:status, name: :outreach_recommendations_status_check)
    |> check_constraint(:action_type, name: :outreach_recommendations_action_type_check)
    |> check_constraint(:recommended_event_kind, name: :outreach_recommendations_event_kind_check)
    |> check_constraint(:confidence, name: :outreach_recommendations_confidence_check)
  end

  def decision_changeset(%__MODULE__{status: "pending"} = recommendation, attrs) do
    recommendation
    |> cast(attrs, [:status, :reviewed_at, :review_reason])
    |> normalize_strings()
    |> validate_required([:status, :reviewed_at])
    |> validate_inclusion(:status, ~w(completed dismissed superseded))
  end

  def decision_changeset(recommendation, _attrs) do
    recommendation
    |> change()
    |> add_error(:status, "must be pending")
  end

  def notification_changeset(recommendation, attrs) do
    recommendation
    |> change(
      Map.take(attrs, [
        :slack_notification_requested_at,
        :slack_notification_posted_at,
        :slack_notification_channel_id,
        :slack_notification_thread_ts
      ])
    )
    |> normalize_strings()
  end

  defp validate_optional_inclusion(changeset, field, values) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_inclusion(changeset, field, values)
    end
  end

  defp validate_channel_draft(changeset) do
    case get_field(changeset, :action_type) do
      "inmail" ->
        validate_required(changeset, [:draft_subject, :draft_message])

      "connection_request" ->
        changeset
        |> reject_subject()
        |> validate_length(:draft_message, max: 200)

      action_type when action_type in ~w(message reply follow_up) ->
        changeset
        |> reject_subject()
        |> validate_required([:draft_message])

      _action_type ->
        changeset
    end
  end

  defp reject_subject(changeset) do
    if get_field(changeset, :draft_subject) do
      add_error(changeset, :draft_subject, "is only supported for InMail")
    else
      changeset
    end
  end

  defp validate_evidence(changeset) do
    case get_field(changeset, :evidence) do
      %{"items" => items} when is_list(items) and items != [] -> changeset
      _evidence -> add_error(changeset, :evidence, "must include at least one item")
    end
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [
        :action_type,
        :recommended_event_kind,
        :title,
        :guidance,
        :rationale,
        :draft_subject,
        :draft_message,
        :generated_by_agent,
        :review_reason,
        :slack_notification_channel_id,
        :slack_notification_thread_ts
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
