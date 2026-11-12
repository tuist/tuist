defmodule Tuist.Runners.APIJobs.Job do
  @moduledoc """
  A runner job created through the public API, under a surrogate
  `workflow_job_id` in its own keyspace.

  `payload` holds what the executor needs and nothing else reads: the script,
  environment, secrets and clone token. It is encrypted, and cleared once the
  job settles.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  @primary_key {:workflow_job_id, :integer, read_after_writes: true}
  schema "runner_api_jobs" do
    field :idempotency_key, :string
    field :name, :string
    field :repository, :string
    field :repository_url, :string
    field :ref, :string, default: ""
    field :commit_sha, :string
    field :payload, Binary, redact: true
    field :cancel_requested_at, :utc_datetime

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:account_id, :idempotency_key, :name, :repository, :repository_url, :ref, :commit_sha, :payload])
    |> validate_required([:account_id, :name, :repository, :repository_url, :commit_sha, :payload])
    |> validate_length(:idempotency_key, min: 1, max: 255)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:repository, min: 1, max: 255)
    |> validate_length(:repository_url, max: 2048)
    |> validate_length(:ref, max: 255)
    |> validate_format(:commit_sha, ~r/\A([0-9a-f]{40}|[0-9a-f]{64})\z/, message: "must be a full lowercase commit SHA")
    |> validate_change(:repository_url, &validate_repository_url/2)
    |> unique_constraint([:account_id, :idempotency_key])
  end

  # The executor clones over HTTPS only, so the clone token never travels in
  # the clear and the URL carries no credentials of its own.
  defp validate_repository_url(field, url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" -> []
      _ -> [{field, "must be an https URL without credentials"}]
    end
  end
end
