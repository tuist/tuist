defmodule Tuist.Runners.Bitrise.Build do
  @moduledoc """
  A Bitrise build queued on a pool Tuist serves, under a surrogate
  `workflow_job_id` in its own keyspace.

  `runner_name` is the runner whose agent took the build, as reported by the
  build's start hook. Bitrise assigns builds to any agent of the pool, so it
  is not necessarily the runner that claimed this row.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Runners.Bitrise.Connection

  @primary_key {:workflow_job_id, :integer, read_after_writes: true}
  schema "runner_bitrise_builds" do
    field :build_slug, :string
    field :app_slug, :string
    field :stack_identifier, :string
    field :build_number, :integer, default: 0
    field :runner_name, :string

    belongs_to :account, Account
    belongs_to :connection, Connection

    timestamps(type: :utc_datetime)
  end

  def changeset(build, attrs) do
    build
    |> cast(attrs, [:account_id, :connection_id, :build_slug, :app_slug, :stack_identifier, :build_number])
    |> validate_required([:account_id, :connection_id, :build_slug, :app_slug, :stack_identifier])
    |> unique_constraint(:build_slug)
  end

  def build_url(%__MODULE__{build_slug: build_slug}), do: "https://app.bitrise.io/build/#{build_slug}"
end
