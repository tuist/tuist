defmodule Tuist.Webhooks do
  @moduledoc """
  Account-scoped webhook endpoints and outbound delivery.

  Endpoints subscribe to one or more event types. When a domain event fires,
  callers dispatch through `Tuist.Webhooks.Dispatcher`, which enqueues a
  `Tuist.Webhooks.Workers.DeliveryWorker` job per subscribed endpoint;
  retries follow the RFC schedule (1m → 5m → 30m → 2h → 8h → 24h).
  """

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Webhooks.Signature
  alias Tuist.Webhooks.WebhookEndpoint

  @doc """
  Lists endpoints in `account_id` that subscribe to `event_type`.
  """
  def list_endpoints_subscribed_to(account_id, event_type) when is_binary(event_type) do
    Repo.all(
      from(e in WebhookEndpoint,
        where: e.account_id == ^account_id,
        where: ^event_type in e.event_types
      )
    )
  end

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

  @delivery_worker "Tuist.Webhooks.Workers.DeliveryWorker"

  @doc """
  Recent delivery attempts for `endpoint_id`, newest first. Each row is a
  flattened view of an Oban job — we don't persist a separate delivery log
  yet, so retries and state collapse into a single record.
  """
  def list_deliveries(endpoint_id, opts \\ []) when is_binary(endpoint_id) do
    limit = Keyword.get(opts, :limit, 50)
    endpoint_id_str = endpoint_id

    Repo.all(
      from(j in "oban_jobs",
        where: j.worker == ^@delivery_worker,
        where: fragment("?->>'webhook_endpoint_id' = ?", j.args, ^endpoint_id_str),
        order_by: [desc: j.inserted_at],
        limit: ^limit,
        select: %{
          id: j.id,
          state: j.state,
          attempt: j.attempt,
          max_attempts: j.max_attempts,
          inserted_at: j.inserted_at,
          scheduled_at: j.scheduled_at,
          attempted_at: j.attempted_at,
          completed_at: j.completed_at,
          discarded_at: j.discarded_at,
          cancelled_at: j.cancelled_at,
          event_id: fragment("?->>'event_id'", j.args),
          event_type: fragment("?->>'event_type'", j.args),
          errors: j.errors
        }
      )
    )
  end

  @doc """
  Aggregate counters across the endpoint's delivery jobs. Used by the
  detail page header. The pending bucket folds both `available` and
  `scheduled` (waiting for retry) into one number.
  """
  def delivery_stats(endpoint_id) when is_binary(endpoint_id) do
    base =
      from(j in "oban_jobs",
        where: j.worker == ^@delivery_worker,
        where: fragment("?->>'webhook_endpoint_id' = ?", j.args, ^endpoint_id)
      )

    rows =
      Repo.all(from j in base, group_by: j.state, select: {j.state, count(j.id)})

    counts = Map.new(rows)

    %{
      total: Enum.reduce(rows, 0, fn {_, n}, acc -> acc + n end),
      delivered: Map.get(counts, "completed", 0),
      failed: Map.get(counts, "discarded", 0) + Map.get(counts, "cancelled", 0) + Map.get(counts, "retryable", 0),
      pending: Map.get(counts, "available", 0) + Map.get(counts, "scheduled", 0)
    }
  end

  @doc """
  Daily delivery counts for the trailing `days` (default 7) — returns one
  entry per day with `total` and `failed` columns, padded with zeros for
  days that had no activity so the chart x-axis stays continuous.
  """
  def deliveries_timeseries(endpoint_id, opts \\ []) when is_binary(endpoint_id) do
    days = Keyword.get(opts, :days, 7)
    today = Date.utc_today()
    since = Date.add(today, -(days - 1))
    since_dt = DateTime.new!(since, ~T[00:00:00], "Etc/UTC")

    rows =
      Repo.all(
        from(j in "oban_jobs",
          where: j.worker == ^@delivery_worker,
          where: fragment("?->>'webhook_endpoint_id' = ?", j.args, ^endpoint_id),
          where: j.inserted_at >= ^since_dt,
          group_by: fragment("date_trunc('day', ?)::date", j.inserted_at),
          select: %{
            date: fragment("date_trunc('day', ?)::date", j.inserted_at),
            total: count(j.id),
            failed: fragment("count(*) filter (where ? in ('discarded', 'cancelled'))", j.state)
          }
        )
      )

    by_date = Map.new(rows, fn %{date: d, total: t, failed: f} -> {d, %{total: t, failed: f}} end)

    Enum.map(0..(days - 1), fn offset ->
      date = Date.add(since, offset)
      values = Map.get(by_date, date, %{total: 0, failed: 0})
      %{date: date, total: values.total, failed: values.failed}
    end)
  end
end
