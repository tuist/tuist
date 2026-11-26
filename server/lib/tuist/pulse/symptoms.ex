defmodule Tuist.Pulse.Symptoms do
  @moduledoc """
  Symptoms are what Pulse surfaces for investigation instead of alert rules.
  The symptoms evaluator (`symptoms/` at the repository root) detects them and
  is the only writer of detection state; this module mirrors its symptom log
  and owns the human state the evaluator reads back (acks, mutes and confirmed
  outcomes). See `symptoms/README.md`, "Systems of record" and "Symptom log".

  ## Mirror

  `sync/1` pulls `GET {base_url}/api/v1/symptoms/log?after=<seq>` with the
  configured bearer token (`Tuist.Environment.symptoms_config/0`) and applies
  each page in one transaction that holds the cursor row's lock, so syncs on
  different nodes take turns:

  - Revisions are handled in `seq` order. A revision becomes the symptom's
    latest (`Tuist.Pulse.Symptom`) only when its `revision` is newer than the
    stored one; every revision handled is kept in
    `Tuist.Pulse.SymptomRevision`, keyed by `symptom_id` and `revision`, so a
    replay is a no-op.
  - A revision with an unknown major `schema_version`, or one that does not
    match the contract, stops the page. What came before it is committed with
    the cursor at the last handled `seq`; the cursor never passes a revision
    that was not handled, so the mirror resumes there once it can read it.
  - Opening or reopening at board or page tier publishes
    `pulse_symptom.opened` after the transaction commits.

  Every symptom in the log belongs to Tuist's own operations
  (`scope.kind == "tuist_ops"`), so the mirror files them under the account
  Pulse is configured for, and every read and action checks
  `Tuist.Pulse.authorized?/2`.

  ## Human state

  Acks, mutes and outcomes carry a `change_seq` from the
  `pulse_symptom_state_changes` sequence. Writers take a transaction-level
  advisory lock before drawing it, so changes commit in `change_seq` order and
  the evaluator's cursor over `state_changes/1` never skips a change that
  commits late.

  The state rows keep only the latest change and overwrite `user_id`. Every
  change also appends a `Tuist.Pulse.SymptomStateEvent` with its user, in the
  same transaction, which the database never lets anyone update or delete
  (`history/2`).
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: KubernetesClient
  alias Tuist.MCP.Events.Publisher
  alias Tuist.Pulse
  alias Tuist.Pulse.Investigations
  alias Tuist.Pulse.Investigations.Investigation
  alias Tuist.Pulse.Symptom
  alias Tuist.Pulse.SymptomAck
  alias Tuist.Pulse.SymptomCursor
  alias Tuist.Pulse.SymptomMute
  alias Tuist.Pulse.SymptomOutcome
  alias Tuist.Pulse.SymptomRevision
  alias Tuist.Pulse.SymptomStateEvent
  alias Tuist.Repo

  require Logger

  @source "evaluator"
  @log_limit 500
  @max_pages 10
  @schema_major "1"
  @state_audience "tuist-symptoms-state"
  @state_limit 500
  @state_lock 7_301_116_180_000
  @max_mute_seconds 30 * 86_400
  @outcomes %{"bad" => :bad, "fine" => :fine}
  @page_size 20
  @ranges %{"24h" => 86_400, "7d" => 7 * 86_400, "30d" => 30 * 86_400}

  @states %{"open" => :open, "resolved" => :resolved, "merged" => :merged}
  @tiers %{"audit" => :audit, "board" => :board, "page" => :page}
  @transitions Map.new(
                 ~w(opened escalated deescalated merged resolved reopened annotated),
                 &{&1, String.to_atom(&1)}
               )
  @phenomena ~w(request_errors latency saturation availability platform_events novelty)

  def phenomena, do: @phenomena

  @doc """
  The audience of the projected ServiceAccount token the evaluator presents to
  `GET /api/internal/symptoms/state`.
  """
  def state_audience, do: @state_audience

  ## Mirror

  @doc """
  Pulls new revisions from the evaluator's log into the mirror for `account`,
  up to #{@max_pages} pages of #{@log_limit}. Returns
  `{:ok, %{applied: n, superseded: n}}`, `{:error, :not_configured}` without a
  URL and token path, or `{:error, reason}` when the log could not be read or a
  revision was rejected (after committing what preceded it).
  """
  def sync(account) do
    with {:ok, client} <- client() do
      pull(account, client, @max_pages, %{applied: 0, superseded: 0})
    end
  end

  defp client do
    config = Environment.symptoms_config()
    url = Keyword.get(config, :base_url)
    token_path = Keyword.get(config, :token_path)

    if is_binary(url) and String.starts_with?(url, ["http://", "https://"]) and is_binary(token_path) and token_path != "",
      do: {:ok, %{base_url: String.trim_trailing(url, "/"), token_path: token_path}},
      else: {:error, :not_configured}
  end

  defp pull(_account, _client, 0, summary), do: {:ok, summary}

  defp pull(account, client, pages, summary) do
    after_seq = cursor()

    with {:ok, revisions} <- fetch_log(client, after_seq) do
      {result, page} = apply_page(account, revisions)
      summary = %{applied: summary.applied + page.applied, superseded: summary.superseded + page.superseded}

      cond do
        result != :ok -> result
        length(revisions) == @log_limit and page.cursor > after_seq -> pull(account, client, pages - 1, summary)
        true -> {:ok, summary}
      end
    end
  end

  defp cursor do
    Repo.one(from(c in SymptomCursor, where: c.source == ^@source, select: c.seq)) || 0
  end

  defp fetch_log(client, after_seq) do
    # A projected token rotates in place. Read it for each page, not at boot
    # or once for an entire multi-page sync.
    with {:ok, raw_token} <- File.read(client.token_path),
         token = String.trim(raw_token),
         true <- token != "" do
      request_log(client.base_url, token, after_seq)
    else
      _ -> {:error, :unavailable}
    end
  end

  defp request_log(base_url, token, after_seq) do
    case Req.get(base_url <> "/api/v1/symptoms/log",
           params: [after: after_seq, limit: @log_limit],
           auth: {:bearer, token},
           headers: [{"accept", "application/json"}],
           receive_timeout: 15_000,
           redirect: false,
           retry: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"revisions" => revisions}}} when is_list(revisions) ->
        {:ok, revisions}

      {:ok, %Req.Response{status: 200}} ->
        {:error, :malformed_response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  defp apply_page(account, revisions) do
    revisions = Enum.sort_by(revisions, &if(is_map(&1) and is_integer(&1["seq"]), do: &1["seq"], else: -1))

    result =
      Repo.transaction(fn ->
        start = lock_cursor()

        {page, opened, error} =
          Enum.reduce_while(
            revisions,
            {%{cursor: start, applied: 0, superseded: 0, latest: []}, [], nil},
            &handle(account, &1, &2)
          )

        # Investigation requests are recorded in the same transaction as the
        # revisions that trigger them, so a replayed page cannot skip or repeat one.
        Investigations.on_applied(account, page.latest)

        if page.cursor > start do
          SymptomCursor
          |> where([c], c.source == ^@source)
          |> Repo.update_all(set: [seq: page.cursor, updated_at: DateTime.truncate(DateTime.utc_now(), :second)])
        end

        # Persist event jobs with the mirror cursor so a failed enqueue or
        # process exit cannot leave a handled opening without its event.
        publish_opened(account, Enum.reverse(opened))
        {page, error}
      end)

    case result do
      {:ok, {page, nil}} ->
        {:ok, page}

      {:ok, {page, error}} ->
        Logger.warning("Pulse symptoms: rejected a symptom log revision: #{inspect(error)}")
        {{:error, error}, page}

      {:error, reason} ->
        {{:error, reason}, %{applied: 0, superseded: 0}}
    end
  end

  # Revisions at or below the cursor were handled by an earlier sync.
  defp handle(account, raw, {page, opened, nil}) do
    case parse(raw) do
      {:ok, %{seq: seq}} when seq <= page.cursor ->
        {:cont, {page, opened, nil}}

      {:ok, revision} ->
        handle_parsed(account, revision, page, opened)

      {:error, reason} ->
        {:halt, {page, opened, reason}}
    end
  end

  defp handle_parsed(account, revision, page, opened) do
    case apply_revision(account, revision) do
      :latest ->
        opened = if opens?(revision), do: [revision | opened], else: opened
        page = %{page | cursor: revision.seq, applied: page.applied + 1, latest: page.latest ++ [revision]}
        {:cont, {page, opened, nil}}

      :superseded ->
        {:cont, {%{page | cursor: revision.seq, superseded: page.superseded + 1}, opened, nil}}
    end
  end

  defp lock_cursor do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(SymptomCursor, [%{source: @source, seq: 0, inserted_at: now, updated_at: now}],
      on_conflict: :nothing,
      conflict_target: [:source]
    )

    SymptomCursor
    |> where([c], c.source == ^@source)
    |> lock("FOR UPDATE")
    |> select([c], c.seq)
    |> Repo.one!()
  end

  # The cursor lock serializes syncs, so reading the stored revision before
  # writing cannot race another sync.
  defp apply_revision(account, revision) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    current = Repo.one(from(s in Symptom, where: s.id == ^revision.id, select: {s.revision, s.max_tier}))

    result =
      case current do
        nil ->
          Repo.insert_all(Symptom, [
            Map.merge(revision.fields, %{
              id: revision.id,
              account_id: account.id,
              max_tier: revision.fields.tier,
              inserted_at: now,
              updated_at: now
            })
          ])

          :latest

        {current, max_tier} when current < revision.revision ->
          fields = Map.merge(revision.fields, %{max_tier: higher_tier(max_tier, revision.fields.tier), updated_at: now})

          Symptom
          |> where([s], s.id == ^revision.id)
          |> Repo.update_all(set: Map.to_list(fields))

          :latest

        {_current, max_tier} ->
          # An older revision still tells which tier the symptom reached.
          Symptom
          |> where([s], s.id == ^revision.id)
          |> Repo.update_all(set: [max_tier: higher_tier(max_tier, revision.fields.tier)])

          :superseded
      end

    Repo.insert_all(
      SymptomRevision,
      [
        %{
          symptom_id: revision.id,
          revision: revision.revision,
          account_id: account.id,
          seq: revision.seq,
          state: revision.fields.state,
          tier: revision.fields.tier,
          transition: revision.fields.transition,
          revised_at: revision.fields.revised_at,
          document: revision.document,
          inserted_at: now
        }
      ],
      on_conflict: :nothing
    )

    result
  end

  @tier_rank %{audit: 0, board: 1, page: 2}

  defp higher_tier(a, b), do: if(@tier_rank[b] > @tier_rank[a], do: b, else: a)

  defp opens?(%{fields: %{transition: transition, tier: tier}}),
    do: transition in [:opened, :reopened] and tier in [:board, :page]

  defp publish_opened(_account, []), do: :ok

  defp publish_opened(account, opened) do
    entries =
      for revision <- opened do
        data = %{
          "account_id" => account.id,
          "symptom_id" => revision.id,
          "tier" => Atom.to_string(revision.fields.tier),
          "service" => revision.fields.service,
          "kind" => revision.fields.entity_kind,
          "key" => revision.fields.entity_key
        }

        {data, "#{revision.id}:#{revision.revision}"}
      end

    Publisher.publish_batch("pulse_symptom.opened", entries, %{"account_id" => account.id})
  end

  # The contract is `symptoms/README.md`, "Symptom log". Minor schema versions
  # only add fields, so they are accepted; nested parts beyond what the page
  # reads are kept as they came.
  defp parse(%{} = raw) do
    with :ok <- schema_version(raw["schema_version"]),
         {:ok, header} <- header(raw),
         {:ok, entity} <- entity(raw["entity"]),
         {:ok, phenomena} <- phenomena(raw["phenomena"]),
         {:ok, times} <- times(raw) do
      fields = header |> Map.merge(entity) |> Map.merge(times) |> Map.merge(details(raw, phenomena))
      {:ok, %{id: header.id, seq: header.seq, revision: header.revision, fields: Map.delete(fields, :id), document: raw}}
    else
      {:error, {:unsupported_schema_version, _}} = error -> error
      _ -> {:error, {:malformed_revision, raw["seq"]}}
    end
  end

  defp parse(_raw), do: {:error, {:malformed_revision, nil}}

  defp schema_version(version) when is_binary(version) do
    [major | _] = String.split(version, ".")

    cond do
      major == @schema_major -> :ok
      match?({_, ""}, Integer.parse(major)) -> {:error, {:unsupported_schema_version, version}}
      true -> :error
    end
  end

  defp schema_version(_version), do: :error

  defp header(%{"seq" => seq, "revision" => revision, "symptom_key" => symptom_key} = raw)
       when is_integer(seq) and seq > 0 and is_integer(revision) and revision > 0 and is_binary(symptom_key) and
              byte_size(symptom_key) <= 128 do
    with {:ok, id} <- Ecto.UUID.cast(raw["symptom_id"]),
         {:ok, state} <- Map.fetch(@states, raw["state"]),
         {:ok, tier} <- Map.fetch(@tiers, raw["tier"]),
         {:ok, transition} <- Map.fetch(@transitions, raw["transition"]),
         {:ok, merged_into} <- optional(&Ecto.UUID.cast/1, raw["merged_into"]) do
      {:ok,
       %{
         id: id,
         symptom_key: symptom_key,
         schema_version: raw["schema_version"],
         revision: revision,
         seq: seq,
         state: state,
         tier: tier,
         transition: transition,
         merged_into: merged_into
       }}
    end
  end

  defp header(_raw), do: :error

  defp times(raw) do
    with {:ok, opened_at} <- timestamp(raw["opened_at"]),
         {:ok, revised_at} <- timestamp(raw["updated_at"]),
         {:ok, resolved_at} <- optional(&timestamp/1, raw["resolved_at"]) do
      {:ok, %{opened_at: opened_at, revised_at: revised_at, resolved_at: resolved_at}}
    end
  end

  # Optional parts: a value of the wrong type is stored as missing.
  defp details(raw, phenomena) do
    impact = map_or_nil(raw["impact"]) || %{}

    %{
      title: if(is_binary(raw["title"]), do: String.slice(raw["title"], 0, 1024)),
      phenomenon_names: phenomena |> Enum.map(& &1["phenomenon"]) |> Enum.uniq(),
      phenomena: phenomena,
      score: number(raw["score"]),
      p_degraded: number(raw["p_degraded"]),
      impact_unit: if(is_binary(impact["unit"]), do: impact["unit"]),
      impact_rate: number(impact["rate"]),
      budget_price: number(raw["budget_price"]),
      decision: map_or_nil(raw["decision"]),
      root: map_or_nil(raw["root"]),
      suspected_change: map_or_nil(raw["suspected_change"]),
      evidence: map_or_nil(raw["evidence"]),
      brief_ref: if(is_binary(raw["brief_ref"]), do: raw["brief_ref"]),
      outcome: map_or_nil(raw["outcome"])
    }
  end

  defp entity(%{"environment" => environment, "service" => service, "kind" => kind, "key" => key})
       when is_binary(environment) and is_binary(service) and is_binary(kind) and is_binary(key) and
              byte_size(service) <= 1024 do
    {:ok, %{environment: environment, service: service, entity_kind: kind, entity_key: key}}
  end

  defp entity(_entity), do: :error

  defp phenomena(phenomena) when is_list(phenomena) do
    if Enum.all?(phenomena, &(is_map(&1) and is_binary(&1["phenomenon"]) and is_number(&1["nats"]))),
      do: {:ok, phenomena},
      else: :error
  end

  defp phenomena(_phenomena), do: :error

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      _ -> :error
    end
  end

  defp timestamp(_value), do: :error

  defp optional(_parse, nil), do: {:ok, nil}
  defp optional(parse, value), do: parse.(value)

  defp number(value) when is_number(value), do: value * 1.0
  defp number(_value), do: nil

  defp map_or_nil(value) when is_map(value), do: value
  defp map_or_nil(_value), do: nil

  ## Reads

  @doc """
  One page of the account's symptoms. String-keyed params, all optional:
  `state` (`open` or `resolved`), `tier` (`audit`, `board` or
  `page`), `phenomenon`, `search` (literal, case-insensitive, over title,
  service and entity key), `sort_by` (`revised_at`, the default, `opened_at`,
  `p_degraded` or `impact_rate`), `sort_order` (`desc`, the default, or `asc`;
  missing values sort last) and `page`. Filtering and sorting precede
  pagination.

  Merged symptoms are always left out: their root stands for them. Without a
  `tier`, symptoms that never reached board or page tier are left out too: the
  evaluator only logs them. A symptom that reached either keeps showing after
  it drops back to audit while quieting down.
  """
  def list(user, account, params) do
    with true <- Pulse.authorized?(user, account),
         {:ok, opts} <- list_params(params) do
      query =
        Symptom
        |> where([s], s.account_id == ^account.id)
        |> where([s], s.state != :merged)
        |> then(&if(opts.state, do: where(&1, [s], s.state == ^opts.state), else: &1))
        |> then(
          &if(opts.tier, do: where(&1, [s], s.tier == ^opts.tier), else: where(&1, [s], s.max_tier in [:board, :page]))
        )
        |> then(
          &if(opts.phenomenon,
            do: where(&1, [s], fragment("? @> ?", s.phenomenon_names, ^[opts.phenomenon])),
            else: &1
          )
        )
        |> search(opts.search)

      total = Repo.aggregate(query, :count)
      total_pages = max(1, ceil(total / @page_size))
      direction = if opts.sort_order == :asc, do: :asc_nulls_last, else: :desc_nulls_last

      rows =
        query
        |> order_by([s], [{^direction, field(s, ^opts.sort_by)}, desc: s.revised_at, asc: s.id])
        |> limit(@page_size)
        |> offset(^((opts.page - 1) * @page_size))
        |> Repo.all()

      {:ok,
       %{
         rows: rows,
         meta: %{
           page: opts.page,
           total_count: total,
           total_pages: total_pages,
           has_previous_page: opts.page > 1,
           has_next_page: opts.page < total_pages
         }
       }}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  @sorts %{
    "revised_at" => :revised_at,
    "opened_at" => :opened_at,
    "p_degraded" => :p_degraded,
    "impact_rate" => :impact_rate
  }

  defp list_params(params) when is_map(params) do
    with {:ok, state} <- optional_value(Map.delete(@states, "merged"), params["state"]),
         {:ok, tier} <- optional_value(@tiers, params["tier"]),
         phenomenon when is_nil(phenomenon) or phenomenon in @phenomena <- blank_to_nil(params["phenomenon"]),
         {:ok, sort_by} <- optional_value(@sorts, Map.get(params, "sort_by", "revised_at")),
         order when order in ["asc", "desc"] <- Map.get(params, "sort_order", "desc"),
         search when is_binary(search) and byte_size(search) <= 4096 <- Map.get(params, "search", ""),
         {page, ""} when page >= 1 and page <= 100_000 <- Integer.parse(to_string(Map.get(params, "page", "1"))) do
      {:ok,
       %{
         state: state,
         tier: tier,
         phenomenon: phenomenon,
         sort_by: sort_by || :revised_at,
         sort_order: String.to_existing_atom(order),
         search: String.trim(search),
         page: page
       }}
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp list_params(_params), do: {:error, :invalid_params}

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp optional_value(_values, value) when value in [nil, ""], do: {:ok, nil}
  defp optional_value(values, value), do: Map.fetch(values, value)

  defp search(query, ""), do: query

  defp search(query, text) do
    pattern = "%" <> String.replace(text, ~r/[\\%_]/, "\\\\\\0") <> "%"

    where(
      query,
      [s],
      ilike(s.title, ^pattern) or ilike(s.service, ^pattern) or ilike(s.entity_key, ^pattern)
    )
  end

  @doc """
  A symptom with its own `phenomenon` (`nil` when its revision has none), its
  100 latest revisions (newest first), its ack, the mutes still in force on its
  entity, and the outcome a person confirmed. Returns
  `{:error, :not_found}` for an unknown ID or another account's symptom.
  """
  def get(user, account, id, now \\ DateTime.utc_now()) do
    with true <- Pulse.authorized?(user, account),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Symptom{} = symptom <- Repo.get_by(Symptom, id: id, account_id: account.id) do
      revisions =
        SymptomRevision
        |> where([r], r.symptom_id == ^id)
        |> order_by([r], desc: r.revision)
        |> limit(100)
        |> Repo.all()

      mutes =
        SymptomMute
        |> where([m], m.account_id == ^account.id and m.expires_at > ^now)
        |> where([m], m.environment == ^symptom.environment and m.service == ^symptom.service)
        |> where([m], m.entity_kind == ^symptom.entity_kind and m.entity_key == ^symptom.entity_key)
        |> order_by([m], asc: m.phenomenon)
        |> Repo.all()

      # The symptom's own phenomenon, the one a mute matches, is kept only in
      # the revision document.
      phenomenon =
        case Enum.find(revisions, &(&1.revision == symptom.revision)) do
          %{document: %{"phenomenon" => phenomenon}} when is_binary(phenomenon) -> phenomenon
          _ -> nil
        end

      {:ok,
       %{
         symptom: symptom,
         phenomenon: phenomenon,
         revisions: revisions,
         ack: Repo.get_by(SymptomAck, symptom_id: id),
         mutes: mutes,
         outcome: Repo.get_by(SymptomOutcome, symptom_id: id)
       }}
    else
      false -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The symptom lifecycle over the window ending now, from revisions, counting
  only symptoms that reached board or page tier (from then on, also after
  dropping back to audit): how many opened and how many resolved, with the same counts for
  the preceding equal window, and how many are open now against the window's
  start. Points are hourly (24h) or daily (7d, 30d), in Unix seconds: counts
  per bucket, and for open symptoms how many were open at the bucket's end.
  `range` is 24h, 7d (the default) or 30d.
  """
  def analytics(user, account, params, now \\ DateTime.utc_now()) do
    range = Map.get(params, "range", "7d")

    with true <- Pulse.authorized?(user, account),
         seconds when is_integer(seconds) <- Map.get(@ranges, range) do
      step = if range == "24h", do: 3600, else: 86_400
      now = DateTime.to_unix(now)
      finish = now - rem(now, step) + step
      start = finish - seconds
      previous_start = start - seconds

      {:ok, %{widgets: lifecycle(revisions_since(account, previous_start), now, {previous_start, start, finish}, step)}}
    else
      false -> {:error, :forbidden}
      _ -> {:error, :invalid_params}
    end
  end

  # Revisions inside the windows, plus each symptom's last revision before
  # them so a symptom already open at the start counts as open, and the
  # symptoms that reached board or page tier before them.
  defp revisions_since(account, previous_start) do
    since = DateTime.from_unix!(previous_start)

    earlier =
      from(r in SymptomRevision,
        where: r.account_id == ^account.id and r.revised_at < ^since,
        distinct: r.symptom_id,
        order_by: [asc: r.symptom_id, desc: r.revision],
        select: {r.symptom_id, r.revision, r.revised_at, r.state, r.tier}
      )

    within =
      from(r in SymptomRevision,
        where: r.account_id == ^account.id and r.revised_at >= ^since,
        select: {r.symptom_id, r.revision, r.revised_at, r.state, r.tier}
      )

    reached_earlier =
      from(r in SymptomRevision,
        where: r.account_id == ^account.id and r.revised_at < ^since and r.tier in [:board, :page],
        distinct: true,
        select: r.symptom_id
      )

    revisions =
      Enum.map(Repo.all(earlier) ++ Repo.all(within), fn {id, revision, at, state, tier} ->
        %{id: id, revision: revision, at: DateTime.to_unix(at), state: state, tier: tier}
      end)

    {revisions, MapSet.new(Repo.all(reached_earlier))}
  end

  defp lifecycle({revisions, reached_earlier}, now, {previous_start, start, finish}, step) do
    buckets = start..(finish - step)//step

    # Like the list, the analytics count only what the evaluator surfaced: a
    # symptom counts from the first revision at board or page tier on, also
    # after it drops back to audit while quieting down. It is open while it
    # is open and has reached either, opens when it becomes so (reopening
    # included) and resolves when it resolves from there.
    timelines = surfaced_timelines(revisions, reached_earlier)

    in_range = fn times, from, to -> Enum.count(times, &(&1 >= from and &1 < to)) end

    # The state at `time` is that of the newest revision made by then.
    open_at = fn time ->
      Enum.count(timelines, fn timeline ->
        match?(%{surfaced: true}, timeline |> Enum.filter(&(&1.at <= time)) |> List.last())
      end)
    end

    changes = Enum.flat_map(timelines, fn timeline -> Enum.zip([%{surfaced: false} | timeline], timeline) end)
    opened = for {previous, r} <- changes, r.surfaced and not previous.surfaced, do: r.at
    resolved = for {previous, r} <- changes, r.state == :resolved and previous.surfaced, do: r.at

    counted =
      for {id, times} <- [{"opened", opened}, {"resolved", resolved}] do
        %{
          id: id,
          value: in_range.(times, start, finish),
          previous_value: in_range.(times, previous_start, start),
          points: for(time <- buckets, do: [time, in_range.(times, time, time + step)])
        }
      end

    open = %{
      id: "open",
      value: open_at.(now),
      previous_value: open_at.(start),
      points: for(time <- buckets, do: [time, open_at.(min(time + step, now))])
    }

    counted ++ [open]
  end

  # Each symptom's revisions in order, each marked `surfaced` when the
  # symptom is open and has reached board or page tier by then.
  defp surfaced_timelines(revisions, reached_earlier) do
    revisions
    |> Enum.group_by(& &1.id)
    |> Enum.map(fn {id, timeline} ->
      timeline
      |> Enum.sort_by(& &1.revision)
      |> Enum.map_reduce(MapSet.member?(reached_earlier, id), fn r, reached ->
        reached = reached or r.tier in [:board, :page]
        {Map.put(r, :surfaced, r.state == :open and reached), reached}
      end)
      |> elem(0)
    end)
  end

  ## Human state

  @doc """
  Acknowledges the symptom at its current revision. Acknowledging again moves
  the ack to the current revision.
  """
  def ack(user, account, id) do
    with {:ok, symptom} <- actionable(user, account, id) do
      record_change(user, account, symptom, :ack, fn change_seq, now ->
        Repo.insert_all(
          SymptomAck,
          [
            %{
              id: UUIDv7.generate(),
              account_id: account.id,
              symptom_id: symptom.id,
              revision: symptom.revision,
              user_id: user.id,
              change_seq: change_seq,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:revision, :user_id, :change_seq, :updated_at]},
          conflict_target: [:symptom_id]
        )

        %{"revision" => symptom.revision}
      end)
    end
  end

  @doc """
  Mutes one of the symptom's phenomena on its entity until `expires_at`, at
  most 30 days ahead. Muting the same entity and phenomenon again replaces the
  expiry.
  """
  def mute(user, account, id, phenomenon, %DateTime{} = expires_at, now \\ DateTime.utc_now()) do
    seconds = DateTime.diff(expires_at, now)

    with {:ok, symptom} <- actionable(user, account, id),
         true <- phenomenon in symptom.phenomenon_names and seconds > 0 and seconds <= @max_mute_seconds do
      record_change(user, account, symptom, :mute, fn change_seq, at ->
        key = scope_key(symptom, phenomenon)
        expires_at = DateTime.truncate(expires_at, :second)

        previous =
          Repo.one(
            from(m in SymptomMute, where: m.account_id == ^account.id and m.scope_key == ^key, select: m.expires_at)
          )

        Repo.insert_all(
          SymptomMute,
          [
            %{
              id: UUIDv7.generate(),
              account_id: account.id,
              scope_key: key,
              environment: symptom.environment,
              service: symptom.service,
              entity_kind: symptom.entity_kind,
              entity_key: symptom.entity_key,
              phenomenon: phenomenon,
              expires_at: expires_at,
              symptom_id: symptom.id,
              user_id: user.id,
              change_seq: change_seq,
              inserted_at: at,
              updated_at: at
            }
          ],
          on_conflict: {:replace, [:expires_at, :symptom_id, :user_id, :change_seq, :updated_at]},
          conflict_target: [:account_id, :scope_key]
        )

        %{
          "phenomenon" => phenomenon,
          "entity" => %{
            "environment" => symptom.environment,
            "service" => symptom.service,
            "kind" => symptom.entity_kind,
            "key" => symptom.entity_key
          },
          "expires_at" => DateTime.to_iso8601(expires_at),
          "previous_expires_at" => previous && DateTime.to_iso8601(previous)
        }
      end)
    else
      false -> {:error, :invalid_params}
      error -> error
    end
  end

  @doc """
  Records the outcome a person confirmed for the symptom: `"bad"` (it was a
  real problem) or `"fine"`. One outcome per symptom; confirming again
  replaces it and moves it to a new `change_seq`.
  """
  def confirm_outcome(user, account, id, outcome) do
    with {:ok, symptom} <- actionable(user, account, id),
         {:ok, outcome} <- Map.fetch(@outcomes, outcome) do
      record_change(user, account, symptom, :outcome, fn change_seq, now ->
        previous = Repo.one(from(o in SymptomOutcome, where: o.symptom_id == ^symptom.id, select: o.outcome))

        Repo.insert_all(
          SymptomOutcome,
          [
            %{
              id: UUIDv7.generate(),
              account_id: account.id,
              symptom_id: symptom.id,
              outcome: outcome,
              user_id: user.id,
              change_seq: change_seq,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: {:replace, [:outcome, :user_id, :change_seq, :updated_at]},
          conflict_target: [:symptom_id]
        )

        %{"outcome" => Atom.to_string(outcome), "previous" => previous && Atom.to_string(previous)}
      end)
    else
      :error -> {:error, :invalid_params}
      error -> error
    end
  end

  defp actionable(user, account, id) do
    with true <- Pulse.authorized?(user, account),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Symptom{} = symptom <- Repo.get_by(Symptom, id: id, account_id: account.id) do
      {:ok, symptom}
    else
      false -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp scope_key(symptom, phenomenon) do
    [symptom.environment, symptom.service, symptom.entity_kind, symptom.entity_key, phenomenon]
    |> Enum.join(<<0>>)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Writes the state row and, in the same transaction, its event. The previous
  # values `write` reads are stable: every writer holds the advisory lock
  # `draw_change_seq/0` takes.
  defp record_change(user, account, symptom, kind, write) do
    {:ok, :ok} =
      Repo.transaction(fn ->
        change_seq = draw_change_seq()
        now = DateTime.truncate(DateTime.utc_now(), :second)
        details = write.(change_seq, now)

        Repo.insert_all(SymptomStateEvent, [
          %{
            id: UUIDv7.generate(),
            account_id: account.id,
            symptom_id: symptom.id,
            kind: kind,
            user_id: user.id,
            change_seq: change_seq,
            details: details,
            inserted_at: now
          }
        ])

        :ok
      end)

    :ok
  end

  @doc """
  Every ack, mute and outcome change ever made to the symptom, oldest first,
  with the user who made it: `%{kind, user_id, change_seq, details,
  inserted_at}`. Unlike the state rows, nothing here is ever overwritten.
  """
  def history(account, symptom_id) do
    SymptomStateEvent
    |> where([e], e.account_id == ^account.id and e.symptom_id == ^symptom_id)
    |> order_by([e], asc: e.change_seq)
    |> select([e], %{
      kind: e.kind,
      user_id: e.user_id,
      change_seq: e.change_seq,
      details: e.details,
      inserted_at: e.inserted_at
    })
    |> Repo.all()
  end

  @doc """
  Draws the next `change_seq` for a human-state row (acks, mutes, outcomes,
  investigations). Call it inside the transaction that writes the row: it
  takes the transaction-level lock that makes changes commit in order.
  """
  def draw_change_seq do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [@state_lock])
    %{rows: [[change_seq]]} = Repo.query!("SELECT nextval('pulse_symptom_state_changes')")
    change_seq
  end

  ## Evaluator read-back

  @doc """
  Authenticates the evaluator's projected ServiceAccount token: it must claim
  the `#{@state_audience}` audience and belong to the configured evaluator
  ServiceAccount. Returns `:ok`, `{:error, :unauthenticated}`,
  `{:error, :not_configured}` or `{:error, :unavailable}`.
  """
  def authenticate_evaluator(token) when is_binary(token) and token != "" do
    with {:ok, principal} <- evaluator_principal(),
         {:ok, %{username: username}} <-
           KubernetesClient.create_bound_token_review(token, @state_audience, timeout: 5_000) do
      if username == principal, do: :ok, else: {:error, :unauthenticated}
    else
      {:error, reason} when reason in [:not_configured, :unauthenticated] -> {:error, reason}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  def authenticate_evaluator(_token), do: {:error, :unauthenticated}

  defp evaluator_principal do
    config = Environment.symptoms_config()
    namespace = Keyword.get(config, :evaluator_namespace)
    name = Keyword.get(config, :evaluator_service_account)

    if is_binary(namespace) and namespace != "" and is_binary(name) and name != "",
      do: {:ok, "system:serviceaccount:#{namespace}:#{name}"},
      else: {:error, :not_configured}
  end

  @doc """
  Human state changed after `after_seq`, at most #{@state_limit} changes in
  `change_seq` order, for the evaluator: acks, mutes (entity, phenomenon and
  expiry), investigations (`Tuist.Pulse.Investigations.state_rows/1`) and
  confirmed outcomes.
  `next` is the cursor to pass next time; it stays at `after_seq` when nothing
  changed. Each row is its latest state, so an ack or mute changed twice
  appears once.
  """
  def state_changes(after_seq) when is_integer(after_seq) and after_seq >= 0 do
    newer = fn schema ->
      schema
      |> where([r], r.change_seq > ^after_seq)
      |> order_by([r], asc: r.change_seq)
      |> limit(@state_limit)
      |> Repo.all()
    end

    changes =
      (newer.(SymptomAck) ++ newer.(SymptomMute) ++ newer.(SymptomOutcome) ++ newer.(Investigation))
      |> Enum.sort_by(& &1.change_seq)
      |> Enum.take(@state_limit)

    by_type = Enum.group_by(changes, & &1.__struct__)

    %{
      "acks" =>
        for ack <- Map.get(by_type, SymptomAck, []) do
          %{
            "symptom_id" => ack.symptom_id,
            "revision" => ack.revision,
            "acked_at" => DateTime.to_iso8601(ack.updated_at),
            "change_seq" => ack.change_seq
          }
        end,
      "mutes" =>
        for mute <- Map.get(by_type, SymptomMute, []) do
          %{
            "entity" => %{
              "environment" => mute.environment,
              "service" => mute.service,
              "kind" => mute.entity_kind,
              "key" => mute.entity_key
            },
            "phenomenon" => mute.phenomenon,
            "expires_at" => DateTime.to_iso8601(mute.expires_at),
            "symptom_id" => mute.symptom_id,
            "change_seq" => mute.change_seq
          }
        end,
      "investigations" => by_type |> Map.get(Investigation, []) |> Investigations.state_rows(),
      "outcomes" =>
        for outcome <- Map.get(by_type, SymptomOutcome, []) do
          %{
            "symptom_id" => outcome.symptom_id,
            "outcome" => Atom.to_string(outcome.outcome),
            "confirmed_at" => DateTime.to_iso8601(outcome.updated_at),
            "change_seq" => outcome.change_seq
          }
        end,
      "next" => if(changes == [], do: after_seq, else: List.last(changes).change_seq)
    }
  end
end
