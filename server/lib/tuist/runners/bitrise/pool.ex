defmodule Tuist.Runners.Bitrise.Pool do
  @moduledoc """
  A self-hosted Bitrise runner pool served by one Tuist runner profile.

  Builds select the pool through its stack (`stack_identifier`). The pool's
  intro secret is what a runner VM registers its agent with, so it is only
  ever handed to a VM that claimed one of the pool's builds.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Runners.Bitrise.Connection
  alias Tuist.Vault.Binary

  schema "runner_bitrise_pools" do
    field :stack_identifier, :string
    field :name, :string
    field :profile_label, :string
    field :intro_secret, Binary, redact: true

    belongs_to :account, Account
    belongs_to :connection, Connection

    timestamps(type: :utc_datetime)
  end

  def changeset(pool, attrs) do
    pool
    |> cast(attrs, [:account_id, :connection_id, :stack_identifier, :name, :profile_label, :intro_secret])
    |> update_change(:stack_identifier, &String.trim/1)
    |> update_change(:intro_secret, &String.trim/1)
    |> validate_required([:account_id, :connection_id, :stack_identifier, :profile_label, :intro_secret])
    |> validate_length(:stack_identifier, max: 255)
    |> unique_constraint([:connection_id, :stack_identifier])
  end
end
