defmodule Tuist.Webhooks do
  @moduledoc """
  Account-scoped webhook endpoints and outbound delivery.

  Endpoints are managed in one place per account and referenced by automation
  `send_webhook` actions across that account's projects. The actual HTTPS POST
  happens asynchronously through `Tuist.Webhooks.Workers.DeliveryWorker`,
  which retries on the RFC schedule (1m → 5m → 30m → 2h → 8h → 24h).
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Webhooks.Signature
  alias Tuist.Webhooks.WebhookEndpoint

  @doc """
  Lists webhook endpoints for `account_id`, oldest-first so the order is
  stable across renders.
  """
  def list_endpoints(account_id) do
    Repo.all(from(e in WebhookEndpoint, where: e.account_id == ^account_id, order_by: [asc: e.inserted_at]))
  end

  @doc """
  Loads a single endpoint by id, regardless of account. Callers that operate
  inside an account scope must compare `account_id` themselves before acting.
  """
  def get_endpoint(id) do
    case Repo.get(WebhookEndpoint, id) do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint}
    end
  end

  @doc """
  Loads an endpoint scoped to `account_id`, ensuring the caller can only
  observe rows that belong to their account.
  """
  def get_account_endpoint(id, account_id) do
    case Repo.one(from(e in WebhookEndpoint, where: e.id == ^id and e.account_id == ^account_id)) do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint}
    end
  end

  @doc """
  Creates an endpoint. The plaintext signing secret is generated server-side
  and returned alongside the persisted struct so the caller can show it to
  the user exactly once.
  """
  def create_endpoint(account_id, attrs) do
    plaintext_secret = Signature.generate_secret()

    attrs =
      attrs
      |> normalize_keys()
      |> Map.put("account_id", account_id)
      |> Map.put("signing_secret", plaintext_secret)

    case %WebhookEndpoint{} |> WebhookEndpoint.create_changeset(attrs) |> Repo.insert() do
      {:ok, endpoint} -> {:ok, endpoint, plaintext_secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def update_endpoint(%WebhookEndpoint{} = endpoint, attrs) do
    endpoint
    |> WebhookEndpoint.update_changeset(normalize_keys(attrs))
    |> Repo.update()
  end

  def delete_endpoint(%WebhookEndpoint{} = endpoint), do: Repo.delete(endpoint)

  @doc """
  Replaces the endpoint's signing secret with a freshly generated one.
  Returns `{:ok, endpoint, plaintext_secret}` so the caller can reveal it
  once before it goes back to encrypted-at-rest.
  """
  def rotate_signing_secret(%WebhookEndpoint{} = endpoint) do
    plaintext = Signature.generate_secret()

    case endpoint |> WebhookEndpoint.rotate_secret_changeset(plaintext) |> Repo.update() do
      {:ok, endpoint} -> {:ok, endpoint, plaintext}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp normalize_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
