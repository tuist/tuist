defmodule Atlas.GTM.Opportunity do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.GTM.OpportunityContact
  alias Atlas.GTM.Signal

  @statuses ~w(new reviewed qualified rejected converted)

  def statuses, do: @statuses

  schema "gtm_opportunities" do
    field :company_key, :string
    field :company_name, :string
    field :domain, :string
    field :status, :string, default: "new"
    field :score, :integer, default: 0
    field :score_breakdown, :map, default: %{}
    field :rationale, :string
    field :signal_summary, :string
    field :latest_signal_at, :utc_datetime
    field :reviewed_at, :utc_datetime
    field :rejected_reason, :string
    field :slack_notification_channel_id, :string
    field :slack_notification_thread_ts, :string
    field :slack_notification_posted_at, :utc_datetime

    belongs_to :account, Account
    has_many :signals, Signal
    has_many :contacts, OpportunityContact

    timestamps()
  end

  def changeset(opportunity, attrs) do
    opportunity
    |> cast(attrs, [
      :company_key,
      :company_name,
      :domain,
      :status,
      :score,
      :score_breakdown,
      :rationale,
      :signal_summary,
      :latest_signal_at,
      :reviewed_at,
      :rejected_reason,
      :slack_notification_channel_id,
      :slack_notification_thread_ts,
      :slack_notification_posted_at
    ])
    |> normalize_string_fields([
      :company_key,
      :company_name,
      :domain,
      :status,
      :rationale,
      :signal_summary,
      :rejected_reason,
      :slack_notification_channel_id,
      :slack_notification_thread_ts
    ])
    |> normalize_domain()
    |> validate_required([:company_key, :company_name, :status, :score])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:company_key)
    |> unique_constraint(:domain)
    |> foreign_key_constraint(:account_id)
  end

  def status_changeset(opportunity, attrs) do
    opportunity
    |> cast(attrs, [:status, :reviewed_at, :rejected_reason])
    |> normalize_string_fields([:status, :rejected_reason])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:account_id)
  end

  def slack_notification_changeset(opportunity, attrs) do
    opportunity
    |> cast(attrs, [
      :slack_notification_channel_id,
      :slack_notification_thread_ts,
      :slack_notification_posted_at
    ])
    |> normalize_string_fields([:slack_notification_channel_id, :slack_notification_thread_ts])
  end

  defp normalize_string_fields(changeset, fields) do
    Enum.reduce(fields, changeset, &normalize_string_field/2)
  end

  defp normalize_string_field(field, changeset) do
    update_change(changeset, field, fn
      nil ->
        nil

      value when is_binary(value) ->
        value
        |> String.trim()
        |> case do
          "" -> nil
          normalized -> normalized
        end

      value ->
        value
    end)
  end

  defp normalize_domain(changeset) do
    update_change(changeset, :domain, fn
      nil ->
        nil

      domain ->
        domain
        |> String.trim()
        |> String.downcase()
        |> String.replace(~r/^https?:\/\//, "")
        |> String.replace(~r/^www\./, "")
        |> String.split("/", parts: 2)
        |> List.first()
        |> case do
          "" -> nil
          normalized -> normalized
        end
    end)
  end
end
