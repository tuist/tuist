defmodule Tuist.Webhooks do
  @moduledoc """
  Account-scoped webhook endpoints and outbound delivery.

  Endpoints subscribe to one or more event types. When a domain event fires,
  callers dispatch through `Tuist.Webhooks.Dispatcher`, which enqueues a
  `Tuist.Webhooks.Workers.DeliveryWorker` job per subscribed endpoint;
  retries follow the RFC schedule (1m → 5m → 30m → 2h → 8h → 24h).
  """

  import Ecto.Query

  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Webhooks.DeliveryAttempt
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

  @doc """
  Recent delivery attempts for `endpoint_id`, newest first.

  Each row is one HTTP attempt against the endpoint — initial send and
  every retry — pulled from the ClickHouse `webhook_delivery_attempts`
  table. Pagination is cursor-based via Flop and returns `{rows, meta}`
  so callers can wire previous/next buttons against `meta.start_cursor`
  / `meta.end_cursor`.

  Supported `opts`:
    * `:page_size` — max rows per page (default 50)
    * `:after` / `:before` — Flop cursor strings (mutually exclusive)
    * `:start_datetime` / `:end_datetime` — restrict by `inserted_at`
    * `:status` — one of `:delivered | :failed`
    * `:event_type` — exact match on `event_type`
    * `:event_id_search` — substring match on `event_id`
  """
  def list_deliveries(endpoint_id, opts \\ []) when is_binary(endpoint_id) do
    base_query =
      from(a in DeliveryAttempt, where: a.webhook_endpoint_id == ^endpoint_id)
      |> apply_period(opts)
      |> apply_status_filter(opts)
      |> apply_event_type_filter(opts)
      |> apply_event_id_search(opts)

    ClickHouseFlop.validate_and_run!(base_query, flop_params(opts), for: DeliveryAttempt)
  end

  defp flop_params(opts) do
    page_size = Keyword.get(opts, :page_size, 50)
    base = %{order_by: [:inserted_at], order_directions: [:desc]}

    cond do
      after_cursor = Keyword.get(opts, :after) ->
        Map.merge(base, %{first: page_size, after: after_cursor})

      before_cursor = Keyword.get(opts, :before) ->
        Map.merge(base, %{last: page_size, before: before_cursor})

      true ->
        Map.put(base, :first, page_size)
    end
  end

  @doc """
  Returns one `DeliveryAttempt` scoped to `endpoint_id`, or
  `{:error, :not_found}`. Used by the event detail page.
  """
  def get_delivery_attempt(endpoint_id, attempt_id) when is_binary(endpoint_id) and is_binary(attempt_id) do
    case ClickHouseRepo.one(
           from(a in DeliveryAttempt,
             where: a.id == ^attempt_id and a.webhook_endpoint_id == ^endpoint_id,
             limit: 1
           )
         ) do
      nil -> {:error, :not_found}
      attempt -> {:ok, attempt}
    end
  end

  @doc """
  Aggregate counters across the endpoint's delivery attempts for the
  given time window. Single-pass scan in ClickHouse via `countIf`.
  """
  def delivery_stats(endpoint_id, opts \\ []) when is_binary(endpoint_id) do
    row =
      from(a in DeliveryAttempt,
        where: a.webhook_endpoint_id == ^endpoint_id,
        select: %{
          total: count(a.id),
          failed: fragment("countIf(? = 'failed')", a.status)
        }
      )
      |> apply_period(opts)
      |> ClickHouseRepo.one()

    case row do
      nil -> %{total: 0, delivered: 0, failed: 0}
      %{total: total, failed: failed} -> %{total: total, delivered: total - failed, failed: failed}
    end
  end

  @doc """
  Per-bucket attempt counts spanning the given window. The bucket size
  is picked from the window length so the chart always renders a sensible
  number of points: hour for ≤2 days, day for ≤90 days, month otherwise.
  Empty buckets are padded with zeros.
  """
  def deliveries_timeseries(endpoint_id, opts \\ []) when is_binary(endpoint_id) do
    {start_dt, end_dt} = period_from_opts(opts)
    unit = bucket_unit_for(start_dt, end_dt)
    rows = timeseries_rows(endpoint_id, start_dt, end_dt, unit)

    by_bucket =
      Map.new(rows, fn %{bucket: b, total: t, failed: f} ->
        {to_utc_datetime(b), %{total: t, failed: f}}
      end)

    bucket_series(start_dt, end_dt, unit, by_bucket)
  end

  defp to_utc_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp to_utc_datetime(%NaiveDateTime{} = ndt), do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

  # Ecto's `fragment/1` requires a literal string as the first argument,
  # so each bucket unit gets its own function clause with the CH
  # `toStartOf...` function inlined.
  defp timeseries_rows(endpoint_id, start_dt, end_dt, :hour) do
    ClickHouseRepo.all(
      from(a in DeliveryAttempt,
        where: a.webhook_endpoint_id == ^endpoint_id,
        where: a.inserted_at >= ^start_dt and a.inserted_at <= ^end_dt,
        group_by: fragment("toStartOfHour(?)", a.inserted_at),
        order_by: fragment("toStartOfHour(?)", a.inserted_at),
        select: %{
          bucket: fragment("toStartOfHour(?)", a.inserted_at),
          total: count(a.id),
          failed: fragment("countIf(? = 'failed')", a.status)
        }
      )
    )
  end

  defp timeseries_rows(endpoint_id, start_dt, end_dt, :day) do
    ClickHouseRepo.all(
      from(a in DeliveryAttempt,
        where: a.webhook_endpoint_id == ^endpoint_id,
        where: a.inserted_at >= ^start_dt and a.inserted_at <= ^end_dt,
        group_by: fragment("toStartOfDay(?)", a.inserted_at),
        order_by: fragment("toStartOfDay(?)", a.inserted_at),
        select: %{
          bucket: fragment("toStartOfDay(?)", a.inserted_at),
          total: count(a.id),
          failed: fragment("countIf(? = 'failed')", a.status)
        }
      )
    )
  end

  defp timeseries_rows(endpoint_id, start_dt, end_dt, :month) do
    ClickHouseRepo.all(
      from(a in DeliveryAttempt,
        where: a.webhook_endpoint_id == ^endpoint_id,
        where: a.inserted_at >= ^start_dt and a.inserted_at <= ^end_dt,
        group_by: fragment("toStartOfMonth(?)", a.inserted_at),
        order_by: fragment("toStartOfMonth(?)", a.inserted_at),
        select: %{
          bucket: fragment("toStartOfMonth(?)", a.inserted_at),
          total: count(a.id),
          failed: fragment("countIf(? = 'failed')", a.status)
        }
      )
    )
  end

  defp apply_period(query, opts) do
    case period_from_opts_or_nil(opts) do
      nil -> query
      {start_dt, end_dt} -> from(a in query, where: a.inserted_at >= ^start_dt and a.inserted_at <= ^end_dt)
    end
  end

  defp apply_status_filter(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> query
      :delivered -> from(a in query, where: a.status == "delivered")
      :failed -> from(a in query, where: a.status == "failed")
      status when status in [:retrying, :pending] -> query
    end
  end

  defp apply_event_type_filter(query, opts) do
    case Keyword.get(opts, :event_type) do
      nil -> query
      "" -> query
      event_type when is_binary(event_type) -> from(a in query, where: a.event_type == ^event_type)
    end
  end

  defp apply_event_id_search(query, opts) do
    case Keyword.get(opts, :event_id_search) do
      nil ->
        query

      "" ->
        query

      term when is_binary(term) ->
        from(a in query, where: fragment("positionCaseInsensitive(?, ?) > 0", a.event_id, ^term))
    end
  end

  defp period_from_opts(opts) do
    case period_from_opts_or_nil(opts) do
      nil ->
        # Default window: trailing 7 days, ending now.
        now = DateTime.truncate(DateTime.utc_now(), :second)
        {DateTime.add(now, -7, :day), now}

      pair ->
        pair
    end
  end

  defp period_from_opts_or_nil(opts) do
    case {Keyword.get(opts, :start_datetime), Keyword.get(opts, :end_datetime)} do
      {%DateTime{} = s, %DateTime{} = e} -> {s, e}
      _ -> nil
    end
  end

  # Pick `:hour`, `:day` or `:month` so the chart x-axis stays readable
  # across the supported presets without forcing the caller to think
  # about granularity.
  defp bucket_unit_for(start_dt, end_dt) do
    hours = DateTime.diff(end_dt, start_dt, :hour)

    cond do
      hours <= 48 -> :hour
      hours <= 24 * 90 -> :day
      true -> :month
    end
  end

  defp bucket_series(start_dt, end_dt, unit, by_bucket) do
    start_bucket = truncate_bucket(start_dt, unit)
    end_bucket = truncate_bucket(end_dt, unit)
    step = bucket_step(unit)

    Stream.unfold(start_bucket, fn bucket ->
      if DateTime.compare(bucket, end_bucket) == :gt do
        nil
      else
        values = Map.get(by_bucket, bucket, %{total: 0, failed: 0})
        {%{bucket: bucket, total: values.total, failed: values.failed}, step.(bucket)}
      end
    end)
    |> Enum.to_list()
  end

  defp truncate_bucket(%DateTime{} = dt, :hour),
    do: %{dt | minute: 0, second: 0, microsecond: {0, 0}}

  defp truncate_bucket(%DateTime{} = dt, :day),
    do: %{dt | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

  defp truncate_bucket(%DateTime{} = dt, :month),
    do: %{dt | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

  defp bucket_step(:hour), do: &DateTime.add(&1, 1, :hour)
  defp bucket_step(:day), do: &DateTime.add(&1, 1, :day)

  defp bucket_step(:month) do
    fn %DateTime{year: y, month: m} = dt ->
      {ny, nm} = if m == 12, do: {y + 1, 1}, else: {y, m + 1}
      %{dt | year: ny, month: nm}
    end
  end
end
