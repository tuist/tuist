defmodule Tuist.Billing.TokenUsage do
  @moduledoc """
  Schema for tracking LLM token usage across all features for billing purposes.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, UUIDv7, autogenerate: true}

  schema "token_usages" do
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :model, :string
    field :feature, :string
    field :feature_resource_id, UUIDv7
    field :timestamp, :utc_datetime

    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating token usage records.
  """
  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:input_tokens, :output_tokens, :model, :feature, :feature_resource_id, :account_id, :timestamp])
    |> validate_required([:input_tokens, :output_tokens, :model, :feature, :feature_resource_id, :account_id, :timestamp])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_inclusion(:feature, ["qa"])
    |> foreign_key_constraint(:account_id)
  end
end
