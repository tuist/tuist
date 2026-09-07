defmodule Tuist.Runners.Buildkite.Installation do
  @moduledoc """
  An account's link to one Buildkite cluster.

  The GitHub lane resolves an account from the webhook's
  `installation.id`, minted by the GitHub App install flow. Buildkite has
  no equivalent handshake: the customer creates a cluster agent token
  (`bkct_…`, which grants access to every self-hosted queue in that
  cluster) and pastes it into their Tuist runner settings. This row is
  that binding.

  `stack_key` identifies us to Buildkite's Stacks API. Reservations are
  scoped to it, so two stacks polling the same cluster do not hand each
  other the same job.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  schema "runner_buildkite_installations" do
    field :organization_slug, :string
    field :stack_key, :string
    field :agent_token, Binary
    field :enabled, :boolean, default: true
    field :last_polled_at, :utc_datetime
    field :last_error, :string
    field :last_error_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  Buildkite caps a stack key at 80 bytes and accepts alphanumerics,
  underscores and dashes only.
  """
  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [
      :account_id,
      :organization_slug,
      :stack_key,
      :agent_token,
      :enabled
    ])
    |> validate_required([:account_id, :organization_slug, :stack_key, :agent_token])
    |> validate_format(:organization_slug, ~r/\A[a-zA-Z0-9._-]+\z/)
    |> validate_format(:stack_key, ~r/\A[a-zA-Z0-9_-]+\z/)
    |> validate_length(:stack_key, max: 80, count: :bytes)
    |> validate_format(:agent_token, ~r/\Abkct_/, message: "must be a Buildkite cluster agent token (starts with bkct_)")
    |> unique_constraint(:account_id)
    |> unique_constraint(:stack_key)
  end
end
