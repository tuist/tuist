defmodule Atlas.Engineering.Errors.IssueAccount do
  @moduledoc """
  Per-(issue, account) counter row. Denormalises the impact of an
  error issue onto Atlas CRM accounts so the impacted-accounts panel,
  enterprise-first ordering, and Slack summary account context can all
  be answered from a single indexed table without joining ClickHouse
  events against Postgres accounts on every read.

  Counters are eventually consistent — bumped by
  `Atlas.Engineering.Errors.IssueAccountCoalescer` at flush time in
  the same shape as `Atlas.Engineering.Errors.IssueCoalescer`. Events
  themselves remain the ClickHouse source of truth.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Engineering.Errors.Issue

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "errors_issues_accounts" do
    field :event_count, :integer, default: 0
    field :first_seen, :utc_datetime_usec
    field :last_seen, :utc_datetime_usec

    belongs_to :issue, Issue
    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:issue_id, :account_id, :event_count, :first_seen, :last_seen])
    |> validate_required([:issue_id, :account_id, :event_count, :first_seen, :last_seen])
    |> unique_constraint([:issue_id, :account_id])
  end
end
