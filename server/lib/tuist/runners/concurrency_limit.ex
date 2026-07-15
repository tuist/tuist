defmodule Tuist.Runners.ConcurrencyLimit do
  @moduledoc """
  The platform-specific resource budget used to coordinate runner
  admission for an account.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  schema "runner_concurrency_limits" do
    field :platform, Ecto.Enum, values: [:linux, :macos]
    field :vcpus, :integer
    field :memory_gb, :integer

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(limit, attrs) do
    limit
    |> cast(attrs, [:account_id, :platform, :vcpus, :memory_gb])
    |> validate_required([:account_id, :platform, :vcpus, :memory_gb])
    |> validate_number(:vcpus, greater_than: 0)
    |> validate_number(:memory_gb, greater_than: 0)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :platform])
  end
end
