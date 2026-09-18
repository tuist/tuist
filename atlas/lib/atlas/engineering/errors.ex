defmodule Atlas.Engineering.Errors do
  @moduledoc """
  Error tracking for Hive: a Sentry-compatible ingest endpoint plus
  the storage that backs it.

  Events land as Sentry envelopes on `POST /api/:project_id/envelope/`,
  are parsed into `Atlas.Engineering.Errors.SentryEvent`, grouped into
  `Atlas.Engineering.Errors.Issue` records by fingerprint (Postgres), and appended
  as rows to the `errors_events` table in ClickHouse.

  This surface is private by design. Errors frequently carry sensitive
  data (user identifiers, request payloads, stack-trace context), so
  every dashboard, feed, and MCP tool that reads issues or events
  requires an authenticated org member. The ingest endpoint itself is
  public but authenticated by DSN public key.

  ## Acceptance semantics

  A `200` on the envelope endpoint means "accepted for ingest", not
  "durable in ClickHouse". Events are parsed inline, the ClickHouse
  row is cast to `Atlas.Engineering.Errors.Event.Buffer`, and the issue upsert is
  cast to `Atlas.Engineering.Errors.IssueCoalescer` — both non-blocking. The buffer
  batches ClickHouse writes on size/time; the coalescer batches
  Postgres upserts per fingerprint. Flush failures on either path are
  logged and reported through `Atlas.Engineering.Errors.DropAlerter`; Sentry SDKs
  cache and retry envelope submission on 5xx, so we never return 5xx
  after DSN validation and rely on the SDK's retry loop for durability.

  The issue id is a deterministic UUIDv5 derived from
  `(project_id, fingerprint)` — see `Atlas.Engineering.Errors.Issue.deterministic_id/2`
  — so the ClickHouse row can name its owning issue in memory without
  waiting on Postgres. Dashboard reads that go through Postgres see
  new issues within the coalescer flush window (default 5 s);
  ClickHouse-backed reads see the event immediately after the buffer
  flush window (default 2 s).
  """

  import Ecto.Query

  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Errors.Availability
  alias Atlas.Engineering.Errors.Envelope
  alias Atlas.Engineering.Errors.Event
  alias Atlas.Engineering.Errors.Fingerprint
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Errors.IssueCoalescer
  alias Atlas.Engineering.Errors.KeyTouches
  alias Atlas.Engineering.Errors.ProjectKey
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Repo

  require Logger

  @doc """
  Whether error tracking is available on this instance. Requires the
  ClickHouse repositories to be started, which is gated by
  `HIVE_CLICKHOUSE_ENABLED`.
  """
  def enabled?, do: Availability.enabled?()

  @doc """
  Ingests a raw Sentry envelope body for a project. Parses each event
  item and hands it to `record_event/3`. Malformed envelopes and
  malformed items are dropped with a warning — never propagated as
  errors to the caller — so the ingest endpoint can always return 200
  once the DSN has been validated (Sentry SDKs never retry on 200 but
  do retry on 5xx, and a stuck malformed envelope would loop forever).

  ## Options

    * `:domain_id` — when the envelope came in through a domain-scoped
      Data Source Name, the domain the credential resolved to. Every
      event in the envelope inherits that attribution.
  """
  def ingest_envelope(%Project{} = project, body, opts \\ []) when is_binary(body) do
    case Envelope.parse(body) do
      {:ok, envelope} ->
        envelope.items
        |> Enum.filter(&(&1.type == "event"))
        |> Enum.each(&ingest_event_item(project, &1, opts))

        :ok

      {:error, reason} ->
        Logger.warning("errors: dropping malformed envelope: #{inspect(reason)}")
        :ok
    end
  end

  defp ingest_event_item(project, item, opts) do
    with {:ok, decoded} <- Jason.decode(item.payload),
         event = SentryEvent.parse(decoded),
         :ok <- record_event(project, event, opts) do
      :ok
    else
      {:error, %Jason.DecodeError{}} ->
        # Malformed SDK input. Not our fault, not worth alerting on.
        :ok

      {:error, :not_configured} ->
        # ClickHouse disabled on this instance (self-hosters without CH).
        # Silent by design so the app keeps working.
        :ok

      {:error, reason} ->
        Logger.warning("errors: dropping event: #{inspect(reason)}")
        Logger.warning("errors: ingest failure reason=#{inspect(reason)} project_id=#{project.id}")
        :ok
    end
  end

  @doc """
  Records a parsed Sentry event against a project. Fires two
  fire-and-forget casts: one to `Atlas.Engineering.Errors.Event.Buffer` (batches
  the ClickHouse insert) and one to `Atlas.Engineering.Errors.IssueCoalescer`
  (batches the Postgres issue upsert and counter bump). Both are
  `GenServer.cast`s, so this call returns after computing the
  deterministic issue id — never blocks on a database round-trip.

  Callers that received raw SDK JSON should build the `SentryEvent` via
  `Atlas.Engineering.Errors.SentryEvent.parse/1` first.

  Pass `:domain_id` in `opts` to attribute the event to a domain — this
  is what a domain-scoped Data Source Name uses to route events into
  their own issue rows independent of the project-level DSN.
  """
  def record_event(project, event, opts \\ [])

  def record_event(%Project{} = project, %SentryEvent{} = event, opts) do
    if enabled?() do
      domain_id = Keyword.get(opts, :domain_id)
      fingerprint = Fingerprint.compute(event)
      # Deterministic id — same `(project_id, domain_id, fingerprint)`
      # always resolves to the same UUID, so the ClickHouse row knows
      # what issue it belongs to without waiting on Postgres. When no
      # domain is attached, the id matches the historical
      # `(project_id, fingerprint)` formula so pre-domain issues stay
      # stable.
      issue_id = Issue.deterministic_id(project.id, domain_id, fingerprint)

      row = build_event_row(project, issue_id, event, fingerprint, domain_id)
      {:ok, _} = Event.Buffer.insert(row)

      :ok =
        IssueCoalescer.observe(IssueCoalescer, project, fingerprint, event, domain_id: domain_id)

      :ok
    else
      {:error, :not_configured}
    end
  rescue
    error -> {:error, error}
  end

  # Builds the ClickHouse row as an `Event` struct. Kept separate from
  # `record_event/3` so its cyclomatic complexity — one branch per
  # string-defaulted column — doesn't blow past Credo's threshold in the
  # outer function.
  defp build_event_row(project, issue_id, event, fingerprint, domain_id) do
    fields =
      core_columns(project, issue_id, event, fingerprint, domain_id)
      |> Map.merge(event_scalar_columns(event))
      |> Map.merge(frame_columns(event.top_frame))
      |> Map.merge(actor_columns(event))
      |> Map.merge(sdk_columns(event))
      |> Map.put(:tags, event.tags)
      |> Map.put(:payload, Jason.encode!(event.payload))

    struct!(Event, fields)
  end

  defp core_columns(project, issue_id, event, fingerprint, domain_id) do
    %{
      event_id: event.event_id |> to_uuid(),
      project_id: project.id,
      domain_id: domain_id || "",
      issue_id: issue_id,
      fingerprint: fingerprint,
      timestamp: DateTime.truncate(event.timestamp, :microsecond),
      received_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp event_scalar_columns(event) do
    %{
      platform: default(event.platform, "other"),
      level: default(event.level, "error"),
      environment: default(event.environment, "production"),
      release: default(event.release, ""),
      dist: default(event.dist, ""),
      server_name: default(event.server_name, ""),
      transaction: default(event.transaction, ""),
      logger: default(event.logger, ""),
      exception_type: default(event.exception_type, ""),
      exception_value: default(event.exception_value, "")
    }
  end

  defp frame_columns(frame) do
    %{
      top_frame_function: frame_field(frame, "function"),
      top_frame_module: frame_field(frame, "module"),
      top_frame_filename: frame_field(frame, "filename")
    }
  end

  defp actor_columns(event) do
    %{
      user_id: default(event.user.id, ""),
      user_email: default(event.user.email, ""),
      user_ip: default(event.user.ip_address, ""),
      request_url: default(event.request.url, ""),
      request_method: default(event.request.method, "")
    }
  end

  defp sdk_columns(event) do
    %{
      sdk_name: default(event.sdk_name, ""),
      sdk_version: default(event.sdk_version, "")
    }
  end

  defp default(nil, fallback), do: fallback
  defp default(value, _fallback), do: value

  defp frame_field(nil, _), do: ""
  defp frame_field(frame, key) when is_map(frame), do: to_string(frame[key] || "")

  defp to_uuid(event_id) when is_binary(event_id) and byte_size(event_id) == 32 do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary-size(12)>> = event_id

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp to_uuid(_), do: Ecto.UUID.generate()

  ## Issue queries

  @doc """
  Lists issues matching the given filters. Options:

    * `:project_id` — scope to a single project (required unless caller has already scoped).
    * `:status` — `:unresolved`, `:resolved`, `:ignored`, or `nil` for all.
    * `:search` — substring against title/culprit.
    * `:from`, `:to` — timeframe on `last_seen`.
    * `:limit`, `:cursor` — cursor-based pagination on `last_seen`.
  """
  def list_issues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    Issue
    |> filter_project(opts[:project_id])
    |> filter_status(opts[:status])
    |> filter_search(opts[:search])
    |> filter_from(opts[:from])
    |> filter_to(opts[:to])
    |> order_by([issue], desc: issue.last_seen, desc: issue.id)
    |> limit(^limit)
    |> preload(:project)
    |> Repo.all()
  end

  @doc """
  Paginated variant of `list_issues/1`. Accepts the same filters plus
  `:page` (1-indexed) and `:page_size` (default 25) and returns
  `{issues, meta}` where meta includes `current_page`, `total_pages`,
  and `total_count`. Suitable for LiveView dashboards.
  """
  def paginate_issues(opts \\ []) do
    page_size = opts |> Keyword.get(:page_size, 25) |> max(1)
    page = opts |> Keyword.get(:page, 1) |> max(1)
    offset = (page - 1) * page_size

    matching_ids =
      issue_ids_matching_events(
        project_id: opts[:project_id],
        environment: opts[:environment],
        from: opts[:from],
        to: opts[:to]
      )

    base =
      Issue
      |> filter_project(opts[:project_id])
      |> filter_status(opts[:status])
      |> filter_search(opts[:search])
      |> filter_from(opts[:from])
      |> filter_to(opts[:to])
      |> filter_matching_ids(matching_ids)

    total = base |> exclude(:preload) |> Repo.aggregate(:count, :id)

    issues =
      base
      |> order_by([issue], desc: issue.last_seen, desc: issue.id)
      |> limit(^page_size)
      |> offset(^offset)
      |> preload(:project)
      |> Repo.all()

    meta = %{
      current_page: page,
      page_size: page_size,
      total_count: total,
      total_pages: max(1, div(total + page_size - 1, page_size)),
      has_previous_page?: page > 1,
      has_next_page?: page * page_size < total
    }

    {issues, meta}
  end

  @doc """
  Returns per-project unresolved issue counts as a
  `%{project_id => count}` map.
  """
  def unresolved_counts_by_project do
    Issue
    |> where([issue], issue.status == :unresolved)
    |> group_by([issue], issue.project_id)
    |> select([issue], {issue.project_id, count(issue.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp filter_project(query, nil), do: query

  defp filter_project(query, project_id), do: where(query, [issue], issue.project_id == ^project_id)

  defp filter_status(query, nil), do: query
  defp filter_status(query, status), do: where(query, [issue], issue.status == ^status)

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, term) when is_binary(term) do
    like = "%#{String.replace(term, "%", "\\%")}%"
    where(query, [issue], ilike(issue.title, ^like) or ilike(issue.culprit, ^like))
  end

  defp filter_from(query, nil), do: query

  defp filter_from(query, %DateTime{} = from), do: where(query, [issue], issue.last_seen >= ^from)

  defp filter_to(query, nil), do: query
  defp filter_to(query, %DateTime{} = to), do: where(query, [issue], issue.last_seen <= ^to)

  defp filter_matching_ids(query, :all), do: query
  defp filter_matching_ids(query, []), do: where(query, [issue], false)

  defp filter_matching_ids(query, ids) when is_list(ids), do: where(query, [issue], issue.id in ^ids)

  def fetch_issue(id) do
    case Repo.get(Issue, id) do
      nil -> {:error, :not_found}
      %Issue{} = issue -> {:ok, Repo.preload(issue, [:project, :assignee])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def update_issue_status(%Issue{} = issue, status) when status in [:unresolved, :resolved, :ignored] do
    issue
    |> Issue.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Resolves unresolved or ignored issues that belong to `project_id`.

  Rows are locked before their status changes so repeated webhook deliveries
  leave an already resolved issue untouched, including its original resolution
  timestamp.
  """
  def resolve_issues(project_id, issue_ids) when is_binary(project_id) and is_list(issue_ids) do
    issue_ids = Enum.uniq(issue_ids)

    if issue_ids == [] do
      {:ok, []}
    else
      Repo.transaction(fn ->
        issues =
          Issue
          |> where(
            [issue],
            issue.project_id == ^project_id and issue.id in ^issue_ids and
              issue.status != :resolved
          )
          |> lock("FOR UPDATE")
          |> Repo.all()

        resolved_at = DateTime.utc_now()
        ids = Enum.map(issues, & &1.id)

        Issue
        |> where([issue], issue.id in ^ids)
        |> Repo.update_all(
          set: [
            status: :resolved,
            resolved_at: resolved_at,
            updated_at: DateTime.truncate(resolved_at, :second)
          ]
        )

        Enum.map(issues, &%{&1 | status: :resolved, resolved_at: resolved_at})
      end)
    end
  end

  ## Project key management

  def list_project_keys(project_id) do
    ProjectKey
    |> where([key], key.project_id == ^project_id and is_nil(key.domain_id))
    |> order_by([key], asc: key.inserted_at)
    |> Repo.all()
  end

  # DSN keys change only on rotation. Cache lookups by public key for
  # `@project_key_cache_ttl` and invalidate on `rotate_project_key/1`
  # and `create_project_key/2`. Miss → PG lookup → cache. Positive
  # results are cached; misses fall through and are not cached so a
  # newly minted key becomes usable within the same request.

  def fetch_project_key_by_public_key(public_key) when is_binary(public_key) do
    case Repo.get_by(ProjectKey, public_key: public_key) do
      nil -> {:error, :not_found}
      %ProjectKey{} = key -> {:ok, Repo.preload(key, :project)}
    end
  end

  defp invalidate_project_key_cache(_public_key), do: :ok

  @doc """
  Provisions a default Data Source Name for the project if one does not
  already exist and error tracking is available. Safe to call from
  contexts that don't know or care whether ClickHouse is enabled —
  returns `:ok` in every branch so callers can chain without a case.
  """
  def ensure_default_key(%Project{id: id}) do
    if enabled?() do
      case list_project_keys(id) do
        [] ->
          case create_project_key(id, %{"name" => "default"}) do
            {:ok, _key} -> :ok
            {:error, _} -> :ok
          end

        _keys ->
          :ok
      end
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  def ensure_default_key(_), do: :ok

  @doc """
  Returns the single Data Source Name for a project — the oldest
  active key. Every project has exactly one at a time; this is how
  the dashboard renders it. Provisions one lazily when missing so
  older projects created before auto-provisioning also render.
  """
  def primary_project_key(%Project{id: id} = project) do
    case list_project_keys(id) do
      [key | _] ->
        key

      [] ->
        ensure_default_key(project)

        case list_project_keys(id) do
          [key | _] -> key
          [] -> nil
        end
    end
  end

  def primary_project_key(_), do: nil

  @doc """
  Deletes every existing key for the project and mints a fresh one.
  Called when an operator suspects a Data Source Name has leaked.
  """
  def rotate_project_key(%Project{id: id}) do
    existing_public_keys =
      ProjectKey
      |> where([k], k.project_id == ^id and is_nil(k.domain_id))
      |> select([k], k.public_key)
      |> Repo.all()

    result =
      Repo.transaction(fn ->
        {_deleted, _} =
          Repo.delete_all(from(k in ProjectKey, where: k.project_id == ^id and is_nil(k.domain_id)))

        case create_project_key(id, %{"name" => "default"}) do
          {:ok, key} -> key
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    Enum.each(existing_public_keys, &invalidate_project_key_cache/1)
    result
  end

  def rotate_project_key(_), do: {:error, :invalid_project}

  def create_project_key(project_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("project_id", project_id)
      |> Map.put_new("public_key", ProjectKey.generate_key())
      |> Map.put_new("secret_key", ProjectKey.generate_key())
      |> Map.put_new("name", "default")

    %ProjectKey{}
    |> ProjectKey.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, %ProjectKey{public_key: public_key}} = ok ->
        # Positive-only cache: an earlier `:not_found` was ignored, so
        # no invalidation is needed. But if a caller previously fetched
        # a cached miss under any code path that DID cache it, this
        # keeps the invariant safe.
        invalidate_project_key_cache(public_key)
        ok

      other ->
        other
    end
  end

  def touch_project_key(%ProjectKey{id: id}) do
    KeyTouches.touch(id)
    :ok
  end

  def touch_project_key(_), do: :ok

  ## Domain-scoped key management
  #
  # A domain-scoped DSN lives in the same `errors_project_keys` table as
  # the project-level one but carries a `domain_id`. Ingested events
  # inherit the domain attribution from the credential, so a service
  # that maps to one domain never has to add an SDK tag to land
  # classified. The URL shape SDKs see is unchanged.

  @doc """
  Lists domain-scoped keys for a given `(project_id, domain_id)` pair,
  oldest first. Excludes project-level keys.
  """
  def list_domain_keys(project_id, domain_id) when is_binary(project_id) and is_binary(domain_id) do
    ProjectKey
    |> where([key], key.project_id == ^project_id and key.domain_id == ^domain_id)
    |> order_by([key], asc: key.inserted_at)
    |> Repo.all()
  end

  @doc """
  Provisions a default domain-scoped Data Source Name for the
  `(project, domain)` pair if none exists yet and error tracking is
  available. Safe to call from contexts that don't know or care whether
  ClickHouse is enabled — returns `:ok` in every branch.
  """
  def ensure_default_domain_key(%Project{id: project_id}, %Domain{id: domain_id}) do
    if enabled?() do
      case list_domain_keys(project_id, domain_id) do
        [] ->
          case create_domain_key(project_id, domain_id, %{"name" => "default"}) do
            {:ok, _key} -> :ok
            {:error, _} -> :ok
          end

        _keys ->
          :ok
      end
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  def ensure_default_domain_key(_, _), do: :ok

  @doc """
  Returns the single Data Source Name for a `(project, domain)` pair —
  the oldest active key. Provisions one lazily when missing so the
  domain page can render a copyable value without a separate
  "provision" step.
  """
  def primary_domain_key(%Project{id: project_id} = project, %Domain{id: domain_id} = domain) do
    case list_domain_keys(project_id, domain_id) do
      [key | _] ->
        key

      [] ->
        ensure_default_domain_key(project, domain)

        case list_domain_keys(project_id, domain_id) do
          [key | _] -> key
          [] -> nil
        end
    end
  end

  def primary_domain_key(_, _), do: nil

  @doc """
  Deletes every existing key for the `(project, domain)` pair and mints
  a fresh one. Called when an operator suspects a domain-scoped Data
  Source Name has leaked. Does not touch the project-level DSN or any
  other domain's DSN.
  """
  def rotate_domain_key(%Project{id: project_id}, %Domain{id: domain_id}) do
    existing_public_keys =
      ProjectKey
      |> where([k], k.project_id == ^project_id and k.domain_id == ^domain_id)
      |> select([k], k.public_key)
      |> Repo.all()

    result =
      Repo.transaction(fn ->
        {_deleted, _} =
          Repo.delete_all(
            from(k in ProjectKey,
              where: k.project_id == ^project_id and k.domain_id == ^domain_id
            )
          )

        case create_domain_key(project_id, domain_id, %{"name" => "default"}) do
          {:ok, key} -> key
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    Enum.each(existing_public_keys, &invalidate_project_key_cache/1)
    result
  end

  def rotate_domain_key(_, _), do: {:error, :invalid_pair}

  def create_domain_key(project_id, domain_id, attrs \\ %{}) when is_binary(project_id) and is_binary(domain_id) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("project_id", project_id)
      |> Map.put("domain_id", domain_id)
      |> Map.put_new("public_key", ProjectKey.generate_key())
      |> Map.put_new("secret_key", ProjectKey.generate_key())
      |> Map.put_new("name", "default")

    %ProjectKey{}
    |> ProjectKey.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, %ProjectKey{public_key: public_key}} = ok ->
        invalidate_project_key_cache(public_key)
        ok

      other ->
        other
    end
  end

  @doc """
  Returns the distinct environments seen for events matching the
  filters. Used by the dashboard's environment filter dropdown.
  """
  def distinct_environments(opts \\ []) do
    if enabled?(), do: do_distinct_environments(opts), else: []
  end

  defp do_distinct_environments(opts) do
    {clauses, params} = event_window_clauses(opts)

    query =
      "SELECT DISTINCT environment FROM errors_events" <>
        where_clause(clauses) <> " ORDER BY environment"

    case Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [env] -> to_string(env) end)
      _ -> []
    end
  end

  @doc """
  Returns the set of issue ids that had at least one event matching
  the given filters. Used to intersect Postgres issue queries with
  event-scoped filters like environment and time window.

  Returns `:all` when ClickHouse is disabled or no filters restrict
  the events, so callers can skip the intersection entirely.
  """
  def issue_ids_matching_events(opts \\ []) do
    cond do
      not enabled?() -> :all
      no_event_scoped_filters?(opts) -> :all
      true -> do_issue_ids_matching_events(opts)
    end
  end

  defp no_event_scoped_filters?(opts) do
    is_nil(Keyword.get(opts, :environment)) and
      is_nil(Keyword.get(opts, :from)) and
      is_nil(Keyword.get(opts, :to))
  end

  defp do_issue_ids_matching_events(opts) do
    {clauses, params} = event_window_clauses(opts)
    query = "SELECT DISTINCT issue_id FROM errors_events" <> where_clause(clauses)

    case Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [id] -> to_string(id) end)
      _ -> []
    end
  end

  defp where_clause([]), do: ""
  defp where_clause(list), do: " WHERE " <> Enum.join(list, " AND ")

  @doc """
  Returns `[{bucket_datetime, count}]` for a single issue, with every
  bucket in the window emitted (zero-filled) so downstream charts have
  a contiguous x-axis.
  """
  def issue_occurrences(issue_id, %DateTime{} = from, %DateTime{} = to) do
    if enabled?() do
      bucket_unit = bucket_unit_for(from, to)
      series = do_event_trends([issue_id], from, to) |> Map.get(issue_id, [])
      buckets = time_buckets(from, to, bucket_unit)
      Enum.zip(buckets, series)
    else
      []
    end
  end

  @doc """
  Returns per-hour event counts for many issues in a single query.
  Result: `%{issue_id => [count_per_bucket]}` ordered oldest → newest.
  Used to render the dashboard's Trend sparkline column without a
  ClickHouse round-trip per row.
  """
  def event_trends(issue_ids, %DateTime{} = from, %DateTime{} = to) when is_list(issue_ids) do
    cond do
      not enabled?() -> %{}
      issue_ids == [] -> %{}
      true -> do_event_trends(issue_ids, from, to)
    end
  end

  defp do_event_trends(issue_ids, from, to) do
    bucket_unit = bucket_unit_for(from, to)

    query = """
    SELECT
      issue_id,
      #{bucket_expr(bucket_unit)} AS bucket,
      count() AS events
    FROM errors_events
    WHERE issue_id IN {ids:Array(String)}
      AND timestamp >= {from:DateTime64(6)}
      AND timestamp <= {to:DateTime64(6)}
    GROUP BY issue_id, bucket
    ORDER BY issue_id, bucket
    """

    params = %{"ids" => issue_ids, "from" => from, "to" => to}

    case Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params) do
      {:ok, %{rows: rows}} ->
        buckets = time_buckets(from, to, bucket_unit)

        by_issue =
          Enum.group_by(rows, fn [issue_id, _bucket, _count] -> to_string(issue_id) end)

        Map.new(issue_ids, fn issue_id ->
          points = Map.get(by_issue, issue_id, [])
          counts_map = Map.new(points, fn [_, bucket, count] -> {bucket_key(bucket), count} end)
          series = Enum.map(buckets, fn bucket -> Map.get(counts_map, bucket_key(bucket), 0) end)
          {issue_id, series}
        end)

      _ ->
        %{}
    end
  end

  defp bucket_unit_for(from, to) do
    hours = DateTime.diff(to, from, :second) / 3600

    cond do
      hours <= 2 -> :minute
      hours <= 24 * 3 -> :hour
      hours <= 24 * 30 -> :day
      true -> :day
    end
  end

  defp bucket_expr(:minute), do: "toStartOfInterval(timestamp, INTERVAL 5 MINUTE)"
  defp bucket_expr(:hour), do: "toStartOfHour(timestamp)"
  defp bucket_expr(:day), do: "toStartOfDay(timestamp)"

  defp time_buckets(from, to, unit) do
    seconds = bucket_seconds(unit)
    start = align_to_bucket(from, seconds)
    stop = to |> DateTime.truncate(:second)

    Stream.iterate(start, &DateTime.add(&1, seconds, :second))
    |> Enum.take_while(&(DateTime.compare(&1, stop) != :gt))
  end

  defp bucket_seconds(:minute), do: 300
  defp bucket_seconds(:hour), do: 3600
  defp bucket_seconds(:day), do: 86_400

  defp align_to_bucket(%DateTime{} = dt, seconds) do
    unix = DateTime.to_unix(dt)
    aligned = div(unix, seconds) * seconds
    DateTime.from_unix!(aligned)
  end

  defp bucket_key(%DateTime{} = dt), do: DateTime.to_unix(dt)

  defp bucket_key(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC") |> DateTime.to_unix()

  defp bucket_key(int) when is_integer(int), do: int

  defp bucket_key(bin) when is_binary(bin) do
    case DateTime.from_iso8601(bin) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> 0
    end
  end

  @doc """
  Fetches a single event by its `event_id` under an issue. Returns
  the same shape as `list_events_for_issue/2` entries or `nil` when
  the event does not exist (or ClickHouse is disabled).

  Accepts the `event_id` either in canonical UUID form
  (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) or as the 32-character
  hex string SDKs and our own randomizer emit.
  """
  def fetch_event(issue_id, event_id) when is_binary(issue_id) and is_binary(event_id) do
    if enabled?() do
      canonical = canonical_event_id(event_id)

      query = """
      SELECT event_id, timestamp, level, environment, release, exception_type,
             exception_value, top_frame_function, top_frame_filename, payload
      FROM errors_events
      WHERE issue_id = {issue_id:String}
        AND event_id = {event_id:UUID}
      LIMIT 1
      """

      params = %{"issue_id" => issue_id, "event_id" => canonical}

      case Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params) do
        {:ok, %{rows: [row]}} -> row_to_event(row)
        _ -> nil
      end
    end
  rescue
    _ -> nil
  end

  def fetch_event(_, _), do: nil

  defp canonical_event_id(
         <<a::binary-size(8), ?-, b::binary-size(4), ?-, c::binary-size(4), ?-, d::binary-size(4), ?-,
           e::binary-size(12)>> = uuid
       )
       when byte_size(uuid) == 36, do: "#{a}-#{b}-#{c}-#{d}-#{e}"

  defp canonical_event_id(hex) when is_binary(hex) and byte_size(hex) == 32 do
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary-size(12)>> = hex

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp canonical_event_id(other), do: other

  defp row_to_event([event_id, ts, level, env, release, ex_type, ex_value, fn_, file, payload]) do
    %{
      event_id: normalize_uuid(event_id),
      timestamp: ts,
      level: level,
      environment: env,
      release: release,
      exception_type: ex_type,
      exception_value: ex_value,
      top_frame_function: fn_,
      top_frame_filename: file,
      payload: safe_decode(payload)
    }
  end

  # ClickHouse returns UUID columns as 16 raw bytes over the wire.
  # Convert to canonical `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` form
  # so callers can render it in URLs and compare against SDK-supplied
  # event ids.
  defp normalize_uuid(<<_::binary-size(16)>> = bin) do
    case Ecto.UUID.load(bin) do
      {:ok, canonical} -> canonical
      _ -> Base.encode16(bin, case: :lower)
    end
  end

  defp normalize_uuid(bin) when is_binary(bin), do: bin
  defp normalize_uuid(other), do: to_string(other)

  @doc """
  Returns per-issue event counts within a time window.
  Result: `%{issue_id => count}`.
  """
  def event_counts_in_window(issue_ids, %DateTime{} = from, %DateTime{} = to) when is_list(issue_ids) do
    cond do
      not enabled?() ->
        %{}

      issue_ids == [] ->
        %{}

      true ->
        query = """
        SELECT issue_id, count() AS events
        FROM errors_events
        WHERE issue_id IN {ids:Array(String)}
          AND timestamp >= {from:DateTime64(6)}
          AND timestamp <= {to:DateTime64(6)}
        GROUP BY issue_id
        """

        params = %{"ids" => issue_ids, "from" => from, "to" => to}

        case Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params) do
          {:ok, %{rows: rows}} ->
            Map.new(rows, fn [id, count] -> {to_string(id), count} end)

          _ ->
            %{}
        end
    end
  end

  defp event_window_clauses(opts) do
    {[], %{}}
    |> add_project_clause(Keyword.get(opts, :project_id))
    |> add_environment_clause(Keyword.get(opts, :environment))
    |> add_from_clause(Keyword.get(opts, :from))
    |> add_to_clause(Keyword.get(opts, :to))
  end

  defp add_project_clause(acc, nil), do: acc

  defp add_project_clause({clauses, params}, pid) do
    {clauses ++ ["project_id = {project_id:String}"], Map.put(params, "project_id", pid)}
  end

  defp add_environment_clause(acc, nil), do: acc
  defp add_environment_clause(acc, ""), do: acc

  defp add_environment_clause({clauses, params}, env) do
    {clauses ++ ["environment = {environment:String}"], Map.put(params, "environment", env)}
  end

  defp add_from_clause(acc, nil), do: acc

  defp add_from_clause({clauses, params}, %DateTime{} = from) do
    {clauses ++ ["timestamp >= {from:DateTime64(6)}"], Map.put(params, "from", from)}
  end

  defp add_to_clause(acc, nil), do: acc

  defp add_to_clause({clauses, params}, %DateTime{} = to) do
    {clauses ++ ["timestamp <= {to:DateTime64(6)}"], Map.put(params, "to", to)}
  end

  @doc """
  Serializes an issue for Model Context Protocol responses.
  """
  def serialize_issue(%Issue{} = issue) do
    project = issue.project

    %{
      id: issue.id,
      url: String.trim_trailing(AtlasWeb.Endpoint.url(), "/") <> "/engineering/errors/#{issue.id}",
      project_id: issue.project_id,
      project_name: project && project.name,
      fingerprint: issue.fingerprint,
      title: issue.title,
      culprit: issue.culprit,
      level: to_string(issue.level),
      platform: issue.platform,
      status: to_string(issue.status),
      event_count: issue.event_count,
      first_seen: issue.first_seen && DateTime.to_iso8601(issue.first_seen),
      last_seen: issue.last_seen && DateTime.to_iso8601(issue.last_seen),
      assignee_id: issue.assignee_id
    }
  end

  @doc """
  Serializes a project key. `endpoint_url` is the Hive host used to
  render the Data Source Name.
  """
  def serialize_project_key(%ProjectKey{} = key, endpoint_url) do
    %{
      id: key.id,
      project_id: key.project_id,
      domain_id: key.domain_id,
      public_key: key.public_key,
      name: key.name,
      dsn: ProjectKey.dsn(key, endpoint_url),
      last_used_at: key.last_used_at && DateTime.to_iso8601(key.last_used_at),
      inserted_at: key.inserted_at && DateTime.to_iso8601(key.inserted_at)
    }
  end

  ## Event queries (ClickHouse)

  @doc """
  Returns a per-hour count of events for the given issue within the
  window. Used by the dashboard occurrence chart and by the alerting
  agent.
  """
  def event_series(issue_id, %DateTime{} = from, %DateTime{} = to) do
    if enabled?() do
      query = """
      SELECT
        toStartOfHour(timestamp) AS bucket,
        count() AS events
      FROM errors_events
      WHERE issue_id = {issue_id:String}
        AND timestamp >= {from:DateTime64(6)}
        AND timestamp <= {to:DateTime64(6)}
      GROUP BY bucket
      ORDER BY bucket
      """

      params = %{"issue_id" => issue_id, "from" => from, "to" => to}

      {:ok, %{rows: rows}} =
        Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params)

      Enum.map(rows, fn [bucket, events] -> %{bucket: bucket, events: events} end)
    else
      []
    end
  end

  @doc """
  Returns the most recent events for an issue as maps, decoding the
  stored payload.
  """
  def list_events_for_issue(issue_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    if enabled?() do
      where_clauses = ["issue_id = {issue_id:String}"]
      params = %{"issue_id" => issue_id, "limit" => limit}

      {where_clauses, params} =
        if from do
          {where_clauses ++ ["timestamp >= {from:DateTime64(6)}"], Map.put(params, "from", from)}
        else
          {where_clauses, params}
        end

      {where_clauses, params} =
        if to do
          {where_clauses ++ ["timestamp <= {to:DateTime64(6)}"], Map.put(params, "to", to)}
        else
          {where_clauses, params}
        end

      query = """
      SELECT event_id, timestamp, level, environment, release, exception_type,
             exception_value, top_frame_function, top_frame_filename, payload
      FROM errors_events
      WHERE #{Enum.join(where_clauses, " AND ")}
      ORDER BY timestamp DESC
      LIMIT {limit:UInt32}
      """

      {:ok, %{rows: rows}} = Ecto.Adapters.SQL.query(Atlas.ClickHouseRepo, query, params)

      Enum.map(rows, fn row -> row_to_event(row) end)
    else
      []
    end
  end

  defp safe_decode(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp safe_decode(_), do: %{}
end
