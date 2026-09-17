defmodule Atlas.Accounts.AccountAttentionSuggestion do
  @moduledoc """
  A durable, evidence-backed recommendation for the next account follow-up.

  Suggestions retain their delivery and resolution history so the agent can
  avoid repeatedly raising the same issue.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  @kinds ~w(follow_up usage_change renewal adoption value_proof relationship)
  @statuses ~w(pending actioned snoozed dismissed)

  schema "account_attention_suggestions" do
    field :status, :string, default: "pending"
    field :kind, :string
    field :suggestion_key, :string
    field :title, :string
    field :rationale, :string
    field :suggested_action, :string
    field :evidence, :map, default: %{"items" => []}
    field :confidence, :decimal
    field :generated_by_agent, :string
    field :snoozed_until, :utc_datetime
    field :resolved_at, :utc_datetime
    field :resolution_note, :string
    field :slack_channel_id, :string
    field :slack_thread_ts, :string
    field :posted_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :account, Account

    timestamps()
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  def changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [
      :status,
      :kind,
      :suggestion_key,
      :title,
      :rationale,
      :suggested_action,
      :evidence,
      :confidence,
      :generated_by_agent,
      :metadata
    ])
    |> normalize_string_fields()
    |> validate_required([
      :account_id,
      :status,
      :kind,
      :suggestion_key,
      :title,
      :rationale,
      :suggested_action,
      :evidence,
      :confidence,
      :generated_by_agent
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_evidence()
    |> foreign_key_constraint(:account_id)
    |> unique_constraint(:suggestion_key, name: :account_attention_suggestions_open_key_index)
    |> check_constraint(:status, name: :account_attention_suggestions_status_check)
    |> check_constraint(:kind, name: :account_attention_suggestions_kind_check)
    |> check_constraint(:confidence, name: :account_attention_suggestions_confidence_check)
  end

  def resolution_changeset(%__MODULE__{status: status} = suggestion, attrs) when status in ["pending", "snoozed"] do
    suggestion
    |> cast(attrs, [:status, :snoozed_until, :resolved_at, :resolution_note])
    |> normalize_string_fields()
    |> validate_inclusion(:status, @statuses -- ["pending"])
    |> validate_resolution()
  end

  def resolution_changeset(suggestion, _attrs) do
    suggestion
    |> change()
    |> add_error(:status, "must be pending or snoozed")
  end

  def delivery_changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [:status, :snoozed_until, :slack_channel_id, :slack_thread_ts, :posted_at])
    |> normalize_string_fields()
  end

  def suggestion_key(kind, topic) do
    normalized_topic =
      topic
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    "#{kind}:#{normalized_topic}"
  end

  defp validate_resolution(changeset) do
    case get_field(changeset, :status) do
      "snoozed" -> validate_required(changeset, [:snoozed_until])
      "actioned" -> validate_required(changeset, [:resolved_at])
      "dismissed" -> validate_required(changeset, [:resolved_at])
      _status -> changeset
    end
  end

  defp validate_evidence(changeset) do
    case get_field(changeset, :evidence) do
      %{"items" => items} when is_list(items) and items != [] -> changeset
      %{"items" => []} -> add_error(changeset, :evidence, "must include at least one item")
      %{} -> add_error(changeset, :evidence, "must include an items list")
      _other -> add_error(changeset, :evidence, "must be a map")
    end
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce(
      [
        :status,
        :kind,
        :suggestion_key,
        :title,
        :rationale,
        :suggested_action,
        :generated_by_agent,
        :resolution_note,
        :slack_channel_id,
        :slack_thread_ts
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
