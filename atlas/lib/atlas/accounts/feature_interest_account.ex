defmodule Atlas.Accounts.FeatureInterestAccount do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.FeatureInterest
  alias Atlas.Support.Thread

  schema "feature_interest_accounts" do
    field :title, :string, virtual: true
    field :summary, :string
    field :notes, :string
    field :last_interested_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :feature_interest, FeatureInterest
    belongs_to :account, Account
    belongs_to :account_event, Event
    belongs_to :support_thread, Thread

    timestamps()
  end

  def changeset(interest_account, attrs) do
    interest_account
    |> cast(attrs, [
      :feature_interest_id,
      :account_id,
      :account_event_id,
      :support_thread_id,
      :title,
      :summary,
      :notes,
      :last_interested_at,
      :metadata
    ])
    |> update_change(:summary, &String.trim/1)
    |> update_change(:title, &String.trim/1)
    |> update_change(:notes, &normalize_optional_text/1)
    |> validate_required([:feature_interest_id, :account_id, :summary, :last_interested_at])
    |> validate_length(:summary, min: 3, max: 2_000)
    |> validate_length(:notes, max: 2_000)
    |> foreign_key_constraint(:feature_interest_id)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:account_event_id)
    |> foreign_key_constraint(:support_thread_id)
    |> unique_constraint([:feature_interest_id, :account_id])
  end

  def form_changeset(interest_account, attrs) do
    interest_account
    |> changeset(attrs)
    |> validate_required([:title])
    |> validate_length(:title, min: 2, max: 160)
  end

  def notes_changeset(interest_account, attrs) do
    interest_account
    |> cast(attrs, [:notes])
    |> update_change(:notes, &normalize_optional_text/1)
    |> validate_length(:notes, max: 2_000)
  end

  defp normalize_optional_text(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
