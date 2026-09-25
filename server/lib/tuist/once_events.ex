defmodule Tuist.OnceEvents do
  @moduledoc """
  Context for the projected state of `once.events.v1` events.

  Writers are the gRPC projector (`Tuist.OnceEvents.Projector`); readers are
  the LiveViews (`TuistWeb.OnceRunsLive`, `TuistWeb.OnceRunLive`) and any
  future API surface.

  PubSub topics:

  * `"once:project:<project_id>"` — a new run or run-state change under this
    project.
  * `"once:run:<project_id>:<run_id>"` — an action was ingested for this run,
    or the run finalized. Payload is `{:run_updated, run_id}` or
    `{:action_ingested, run_id}`. Scoped by project because the run id is
    chosen by the client.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Phoenix.PubSub
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.CacheEvent
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.SystemSample
  alias Tuist.OnceEvents.TestCaseRun
  alias Tuist.OnceEvents.TestSuiteRun
  alias Tuist.Repo

  @pubsub Tuist.PubSub

  # ---- Writes -----------------------------------------------------------

  @doc """
  Claim the right to publish `run`'s results to the shared test store,
  returning `:ok` to exactly one caller and `:already_published` to the rest.

  The claim is a conditional update rather than a read followed by a write:
  two projectors handling the same replayed `RunCompleted` would both pass a
  read check and then append a second copy of every module, suite and case,
  since `Tuist.Tests.create_test/1` generates fresh ids for those children.
  """
  def claim_test_report_publication(%Run{} = run) do
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    {claimed, _} =
      Run
      |> where([r], r.id == ^run.id and is_nil(r.test_report_published_at))
      |> Repo.update_all(set: [test_report_published_at: now, updated_at: now])

    if claimed == 1, do: :ok, else: :already_published
  end

  @doc """
  Release a claim taken by `claim_test_report_publication/1` when publishing
  failed, so the run can be retried on the next `RunCompleted` replay rather
  than being permanently skipped.
  """
  def release_test_report_publication(%Run{} = run) do
    Run
    |> where([r], r.id == ^run.id)
    |> Repo.update_all(set: [test_report_published_at: nil])

    :ok
  end

  @doc """
  Every test case staged for `run`, oldest first. This is what
  `Tuist.OnceEvents.TestReportIngestor` assembles the shared report from,
  since `RunCompleted` carries only per-result counts.
  """
  def list_test_case_runs(%Run{} = run) do
    TestCaseRun
    |> where([c], c.once_run_id == ^run.id)
    |> order_by([c], asc: c.finished_at, asc: c.id)
    |> Repo.all()
  end

  @doc """
  Upsert a run when its RunStarted event lands. Idempotent on
  `(project_id, run_id)`.
  """
  def upsert_run(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)
    attrs = truncate_datetimes(attrs, [:started_at, :finalized_at, :heartbeat_at])

    on_conflict =
      [
        set: [
          once_version: Map.get(attrs, :once_version),
          protocol_version: Map.get(attrs, :protocol_version),
          host_class: Map.get(attrs, :host_class),
          is_ci: Map.get(attrs, :is_ci, false),
          git_rev: Map.get(attrs, :git_rev),
          git_branch: Map.get(attrs, :git_branch) || "",
          git_dirty: Map.get(attrs, :git_dirty, false),
          argv_normalized: Map.get(attrs, :argv_normalized, %{}),
          argv_hash_key_id: Map.get(attrs, :argv_hash_key_id),
          safe_literal_allowlist_version: Map.get(attrs, :safe_literal_allowlist_version),
          cwd_relative: Map.get(attrs, :cwd_relative),
          env_fingerprint: Map.get(attrs, :env_fingerprint),
          root_graph_digest: Map.get(attrs, :root_graph_digest, %{}),
          effective_limits: Map.get(attrs, :effective_limits, %{}),
          command_display: Map.get(attrs, :command_display),
          kind: Map.get(attrs, :kind, "build"),
          heartbeat_at: now,
          updated_at: now
        ]
      ]

    attrs = Map.put_new(attrs, :started_at, now)

    result =
      %Run{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert(
        on_conflict: on_conflict,
        conflict_target: [:project_id, :run_id],
        returning: true
      )

    with {:ok, run} <- result do
      broadcast_project(run.project_id, {:run_updated, run.run_id})
      broadcast_run(run, {:run_updated, run.run_id})
      {:ok, run}
    end
  end

  @doc """
  Insert one action's terminal state under a run, keeping the parent run's
  roll-ups in sync in a single transaction so a projector crash never
  publishes a half-updated run.
  """
  def ingest_action(%Run{} = run, attrs) do
    action_attrs =
      attrs
      |> Map.put(:once_run_id, run.id)
      |> Map.put(:run_id, run.run_id)
      |> Map.put(:project_id, run.project_id)
      |> truncate_datetimes([:started_at, :finished_at])

    # Synthetic phase spans (capability `_phase` — analysis,
    # materialize_outputs, etc.) ride the same table so the timeline
    # picks them up automatically, but they are not real actions:
    # skip them in `total_actions` / `cached_actions` / roll-up so
    # the Overview card's counters keep their user-facing meaning.
    synthetic? = action_attrs[:capability] == "_phase"

    delta =
      if synthetic? do
        %{}
      else
        %{
          total_actions: 1,
          cached_actions: if(action_attrs[:was_cached], do: 1, else: 0),
          executed_actions: if(action_attrs[:was_cached], do: 0, else: 1),
          failed_actions: if(action_attrs[:result] == "failed", do: 1, else: 0)
        }
      end

    multi =
      Multi.new()
      |> Multi.run(:action, fn repo, _ ->
        now = DateTime.truncate(DateTime.utc_now(), :microsecond)
        attrs = Map.merge(action_attrs, %{id: UUIDv7.generate(), inserted_at: now, updated_at: now})

        {count, actions} =
          repo.insert_all(Action, [attrs],
            on_conflict: :nothing,
            conflict_target: [:once_run_id, :target_execution_id, :capability, :action_index],
            returning: true
          )

        {:ok, {count, List.first(actions)}}
      end)
      |> Multi.run(:rollup, fn repo, %{action: {count, _}} ->
        if count == 1 and not synthetic? do
          repo.update_all(
            from(r in Run, where: r.id == ^run.id),
            inc: Map.to_list(delta),
            set: [heartbeat_at: DateTime.truncate(DateTime.utc_now(), :microsecond)]
          )
        end

        {:ok, count}
      end)

    case Repo.transaction(multi) do
      {:ok, %{action: {_count, action}}} ->
        broadcast_run(run, {:action_ingested, run.run_id})
        {:ok, action}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Mark a run finalized. Idempotent; a late `RunCompleted` after
  `FINALIZATION_PENDING` still transitions to `finalized` within the dedup
  window.
  """
  def finalize_run(%Run{} = run, attrs) do
    finalized_at = DateTime.truncate(Map.get(attrs, :finalized_at) || DateTime.utc_now(), :microsecond)

    changeset =
      Ecto.Changeset.change(run,
        finalization: Map.get(attrs, :finalization, "finalized"),
        exit_status: Map.get(attrs, :exit_status),
        cancellation_reason: Map.get(attrs, :cancellation_reason),
        wall_ms: Map.get(attrs, :wall_ms),
        finalized_at: finalized_at
      )

    with {:ok, updated} <- Repo.update(changeset) do
      broadcast_project(updated.project_id, {:run_updated, updated.run_id})
      broadcast_run(updated, {:run_updated, updated.run_id})
      {:ok, updated}
    end
  end

  @doc """
  Insert one cache event and roll it up into the parent run's cache
  counters in one transaction. Idempotent on
  `(once_run_id, kind, target_execution_id, content_hash,
  observed_at)`; a resend after a stream break replays cleanly.
  """
  def ingest_cache_event(%Run{} = run, attrs) do
    event_attrs =
      attrs
      |> Map.put(:once_run_id, run.id)
      |> Map.put(:run_id, run.run_id)
      |> Map.put(:project_id, run.project_id)
      |> truncate_datetimes([:observed_at])

    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    event_attrs =
      event_attrs
      |> Map.put_new(:observed_at, now)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    # The transport replays a batch whenever an ack is lost, so the row
    # id is derived from the event's own identity rather than generated.
    # A replayed event then collides on the primary key, `on_conflict:
    # :nothing` drops it, and the `count == 1` guard below keeps the
    # run's byte and latency roll-ups from being applied twice.
    event_attrs = Map.put(event_attrs, :id, cache_event_id(event_attrs))

    kind = Map.get(event_attrs, :kind)
    bytes = Map.get(event_attrs, :bytes_transferred, 0)
    duration = Map.get(event_attrs, :duration_ms, 0)

    run_delta =
      case kind do
        "download" ->
          %{
            cache_bytes_downloaded: bytes,
            cache_action_read_count: 1,
            cache_action_read_ms_total: duration
          }

        "upload" ->
          %{
            cache_bytes_uploaded: bytes,
            cache_action_write_count: 1,
            cache_action_write_ms_total: duration
          }

        "reused" ->
          %{cache_bytes_saved: Map.get(event_attrs, :content_size_bytes, 0)}

        _ ->
          %{}
      end

    multi =
      Multi.new()
      |> Multi.run(:event, fn repo, _ ->
        {count, _} =
          repo.insert_all(CacheEvent, [event_attrs],
            on_conflict: :nothing,
            conflict_target: :id
          )

        {:ok, count}
      end)
      |> Multi.run(:rollup, fn repo, %{event: count} ->
        if count == 1 and run_delta != %{} do
          repo.update_all(
            from(r in Run, where: r.id == ^run.id),
            inc: Map.to_list(run_delta),
            set: [heartbeat_at: DateTime.truncate(DateTime.utc_now(), :microsecond)]
          )
        end

        {:ok, count}
      end)

    case Repo.transaction(multi) do
      {:ok, _} ->
        broadcast_run(run, {:cache_event_ingested, run.run_id})
        :ok

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Insert one SystemSampled event. Idempotent on `(once_run_id,
  at_ms)`; a resend replays cleanly.
  """
  def ingest_system_sample(%Run{} = run, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)
    observed_at = DateTime.truncate(Map.get(attrs, :observed_at) || now, :microsecond)

    row = %{
      id: UUIDv7.generate(),
      once_run_id: run.id,
      run_id: run.run_id,
      project_id: run.project_id,
      at_ms: Map.get(attrs, :at_ms),
      cpu_percent: Map.get(attrs, :cpu_percent, 0.0),
      memory_bytes: Map.get(attrs, :memory_bytes, 0),
      network_in_bytes: Map.get(attrs, :network_in_bytes, 0),
      network_out_bytes: Map.get(attrs, :network_out_bytes, 0),
      observed_at: observed_at
    }

    {_count, _} = Repo.insert_all(SystemSample, [row], on_conflict: :nothing)
    broadcast_run(run, {:system_sampled, run.run_id})
    :ok
  end

  @doc """
  Upsert one suite's row and (on completion) refresh its per-case
  counters + finished_at. Suite rows are created on start and
  updated on completion so the Tests page can display a live "N of
  M cases" progress while the suite is still running.
  """
  def ingest_test_suite_run(%Run{} = run, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)
    target = safe_string_or_nil(Map.get(attrs, :target_execution_id))
    suite = safe_string_or_nil(Map.get(attrs, :suite_id)) || target || ""

    row =
      %{
        id: UUIDv7.generate(),
        once_run_id: run.id,
        run_id: run.run_id,
        project_id: run.project_id,
        target_execution_id: target,
        suite_id: suite,
        planned_case_count: Map.get(attrs, :planned_case_count),
        total_cases: Map.get(attrs, :total_cases, 0),
        passed_cases: Map.get(attrs, :passed_cases, 0),
        failed_cases: Map.get(attrs, :failed_cases, 0),
        skipped_cases: Map.get(attrs, :skipped_cases, 0),
        errored_cases: Map.get(attrs, :errored_cases, 0),
        timed_out_cases: Map.get(attrs, :timed_out_cases, 0),
        cancelled_cases: Map.get(attrs, :cancelled_cases, 0),
        duration_ms: Map.get(attrs, :duration_ms, 0),
        started_at: maybe_truncate(Map.get(attrs, :started_at)) || now,
        finished_at: maybe_truncate(Map.get(attrs, :finished_at)),
        inserted_at: now,
        updated_at: now
      }

    # A start-only row must not clobber a completion row's totals,
    # so `on_conflict` cherry-picks the fields the current message
    # actually carried. `finished_at` only advances forward.
    update_fields =
      maybe_replace_totals(
        [
          set: [
            planned_case_count: dynamic_coalesce(:planned_case_count, row.planned_case_count),
            finished_at: dynamic_coalesce(:finished_at, row.finished_at)
          ]
        ],
        row
      )

    Repo.insert_all(TestSuiteRun, [row],
      on_conflict: update_fields,
      conflict_target: [:once_run_id, :target_execution_id, :suite_id]
    )

    # Counted from the suite rows rather than incremented. An upsert
    # cannot tell an insert from an update through `returning` here
    # (`update_fields` deliberately leaves `updated_at` alone so a
    # start-only event does not clobber a completion), so a replayed
    # `TestSuiteStarted` would otherwise look fresh and inflate the
    # count on every retry.
    suite_count_query =
      from(s in TestSuiteRun, where: s.once_run_id == ^run.id, select: count(s.id))

    Repo.update_all(
      from(r in Run, where: r.id == ^run.id),
      set: [test_suite_count: Repo.one(suite_count_query), heartbeat_at: now]
    )

    broadcast_run(run, {:test_suite_ingested, run.run_id})
    :ok
  end

  @doc """
  Insert one test-case attempt row and bump the parent run's test
  roll-ups in one transaction so the Overview counters stay in sync.
  Rows are unique per `(once_run_id, case_id, attempt)`, so a retry
  produces a new row and the passed/failed rollup counts each
  attempt independently.
  """
  def ingest_test_case_run(%Run{} = run, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)
    row = test_case_row(run, attrs, now)

    {:ok, _} =
      Repo.transaction(fn ->
        {count, _} =
          Repo.insert_all(TestCaseRun, [row],
            on_conflict: :nothing,
            conflict_target: [:once_run_id, :case_id, :attempt]
          )

        if count == 1, do: roll_up_test_case(run, row, now)
      end)

    broadcast_run(run, {:test_case_ingested, run.run_id})
    :ok
  end

  # Helpers -------------------------------------------------------------

  defp test_case_row(%Run{} = run, attrs, now) do
    %{
      id: UUIDv7.generate(),
      once_run_id: run.id,
      run_id: run.run_id,
      project_id: run.project_id,
      target_execution_id: safe_string_or_nil(Map.get(attrs, :target_execution_id)),
      suite_id: safe_string_or_nil(Map.get(attrs, :suite_id)),
      case_id: safe_string(Map.get(attrs, :case_id, "")),
      name: safe_string(Map.get(attrs, :name, "")),
      class_name: safe_string_or_nil(Map.get(attrs, :class_name)),
      module: safe_string_or_nil(Map.get(attrs, :module)),
      attempt: Map.get(attrs, :attempt, 1),
      result: safe_string(Map.get(attrs, :result, "unknown")),
      duration_ms: Map.get(attrs, :duration_ms, 0),
      failure_message: safe_string_or_nil(Map.get(attrs, :failure_message)),
      started_at: maybe_truncate(Map.get(attrs, :started_at)),
      finished_at: maybe_truncate(Map.get(attrs, :finished_at)) || now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp roll_up_test_case(%Run{} = run, row, now) do
    Repo.update_all(
      from(r in Run, where: r.id == ^run.id),
      inc: run_test_case_inc(row.result),
      set: [heartbeat_at: now]
    )

    # A completion also advances the parent suite's per-result counters if
    # a suite row exists. One write per case keeps suite totals live for
    # the Tests page.
    Repo.update_all(
      from(s in TestSuiteRun,
        where: s.once_run_id == ^run.id and s.suite_id == ^(row.suite_id || "")
      ),
      inc: suite_case_inc(row.result),
      set: [updated_at: now]
    )

    :ok
  end

  defp run_test_case_inc(result) do
    [
      test_case_count: 1,
      passed_test_cases: if(result == "passed", do: 1, else: 0),
      failed_test_cases: if(result == "failed", do: 1, else: 0),
      skipped_test_cases: if(result == "skipped", do: 1, else: 0)
    ]
  end

  @suite_case_counters %{
    "passed" => :passed_cases,
    "failed" => :failed_cases,
    "skipped" => :skipped_cases,
    "errored" => :errored_cases,
    "timed_out" => :timed_out_cases,
    "cancelled" => :cancelled_cases
  }

  defp suite_case_inc(result) do
    case Map.fetch(@suite_case_counters, result) do
      {:ok, counter} -> [{:total_cases, 1}, {counter, 1}]
      :error -> [total_cases: 1]
    end
  end

  # A cache event has no id of its own on the wire, so one is derived
  # from the fields that identify it within a run. Two events that agree
  # on all of them are the same observation replayed, not two transfers:
  # a genuine second transfer of the same object differs in at least
  # `observed_at`, which the producer stamps per event.
  defp cache_event_id(attrs) do
    [
      attrs[:once_run_id],
      attrs[:kind],
      attrs[:category],
      attrs[:target_execution_id],
      attrs[:content_hash],
      attrs[:cache_decision_id],
      attrs[:outcome],
      attrs[:observed_at] && DateTime.to_iso8601(attrs[:observed_at]),
      attrs[:bytes_transferred],
      attrs[:content_size_bytes]
    ]
    |> Enum.map_join("\0", &to_string/1)
    |> uuid_from_seed()
  end

  @doc """
  Formats the first 16 bytes of a SHA-256 digest as a UUID so the value fits
  a `uuid` column. The version and variant nibbles are stamped to keep it a
  well-formed v5-style name-based UUID, so the same seed always yields the
  same id and a replay stays idempotent.
  """
  def uuid_from_seed(seed) do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48, _rest::binary>> =
      :crypto.hash(:sha256, seed)

    <<a::32, b::16, 5::4, c::12, 2::2, d::14, e::48>>
    |> Base.encode16(case: :lower)
    |> then(fn <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> ->
      "#{p1}-#{p2}-#{p3}-#{p4}-#{p5}"
    end)
  end

  defp maybe_truncate(nil), do: nil

  defp maybe_truncate(%DateTime{} = dt), do: DateTime.truncate(dt, :microsecond)

  defp safe_string_or_nil(nil), do: nil
  defp safe_string_or_nil(""), do: nil
  defp safe_string_or_nil(str) when is_binary(str), do: str

  defp safe_string(nil), do: ""
  defp safe_string(""), do: ""
  defp safe_string(str) when is_binary(str), do: str
  defp safe_string(_), do: ""

  # Only overwrite the totals when the incoming attrs actually carry
  # them (i.e. a suite-completion event). A suite-start event leaves
  # every count at its default 0, so we skip the SET clause to avoid
  # zeroing an already-populated row.
  defp maybe_replace_totals(update_fields, row) do
    if row.total_cases > 0 or row.finished_at != nil do
      totals = [
        total_cases: row.total_cases,
        passed_cases: row.passed_cases,
        failed_cases: row.failed_cases,
        skipped_cases: row.skipped_cases,
        errored_cases: row.errored_cases,
        timed_out_cases: row.timed_out_cases,
        cancelled_cases: row.cancelled_cases,
        duration_ms: row.duration_ms
      ]

      Keyword.update!(update_fields, :set, &(&1 ++ totals))
    else
      update_fields
    end
  end

  defp dynamic_coalesce(field, incoming), do: dynamic([r], fragment("coalesce(?, ?)", ^incoming, field(r, ^field)))

  @doc """
  List every SystemSampled sample for a run in wall-clock order.
  Bounded by the shortest of the run's finalized wall-time and the
  raw row count; the Timeline LiveView pulls the whole series in one
  shot because a full 30-minute build at 1 Hz is 1800 rows.
  """
  def list_system_samples(%Run{} = run) do
    SystemSample
    |> where([s], s.once_run_id == ^run.id)
    |> order_by([s], asc: s.at_ms)
    |> Repo.all()
  end

  # ---- Reads ------------------------------------------------------------

  @doc """
  List runs for a project, most-recent first, paginated at the DB level.
  Filters by kind so the Builds and Tests pages ask distinct questions.
  """
  def list_runs(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    kind = Keyword.get(opts, :kind)

    Run
    |> where([r], r.project_id == ^project_id)
    |> maybe_filter_kind(kind)
    |> order_by([r], desc: r.started_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Count runs for a project. Filter by kind for the Builds/Tests pages.
  """
  def count_runs(project_id, opts \\ []) do
    kind = Keyword.get(opts, :kind)

    Run
    |> where([r], r.project_id == ^project_id)
    |> maybe_filter_kind(kind)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Fetch one run scoped to a project. `nil` when not found.
  """
  def get_run(project_id, run_id) do
    Run
    |> where([r], r.project_id == ^project_id and r.run_id == ^run_id)
    |> Repo.one()
  end

  @doc """
  List actions under a run, applying search and filters before sorting and pagination.
  """
  def list_actions(%Run{} = run, opts \\ []) do
    sort_field =
      Map.get(
        %{
          "action" => :identifier,
          "status" => :result,
          "cache" => :was_cached,
          "duration" => :duration_ms,
          "finished" => :finished_at
        },
        Keyword.get(opts, :sort_by),
        :target_execution_id
      )

    direction = if Keyword.get(opts, :sort_order) == "desc", do: :desc_nulls_last, else: :asc_nulls_last

    run
    |> actions_query(opts)
    |> order_by([a], [
      {^direction, field(a, ^sort_field)},
      asc: a.target_execution_id,
      asc: a.capability,
      asc: a.action_index,
      asc: a.id
    ])
    |> limit(^Keyword.get(opts, :limit, 50))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  def count_actions(%Run{} = run, opts \\ []) do
    run |> actions_query(opts) |> Repo.aggregate(:count)
  end

  defp actions_query(run, opts) do
    query = where(Action, [a], a.once_run_id == ^run.id)
    search = opts |> Keyword.get(:search, "") |> String.trim()

    query =
      if search == "" do
        query
      else
        pattern = "%" <> String.replace(search, ~r/[\\%_]/, fn char -> "\\" <> char end) <> "%"
        where(query, [a], ilike(a.identifier, ^pattern) or ilike(a.target_execution_id, ^pattern))
      end

    Enum.reduce(Keyword.get(opts, :filters, []), query, &filter_actions/2)
  end

  defp filter_actions(%{field: :result, op: op, value: value}, query)
       when op in [:==, :!=] and
              value in ["succeeded", "failed", "skipped", "cancelled", "timed_out", "infrastructure_error", "unknown"] do
    if op == :==, do: where(query, [a], a.result == ^value), else: where(query, [a], a.result != ^value)
  end

  defp filter_actions(%{field: :cache, op: op, value: value}, query) when op in [:==, :!=] and value in ["hit", "miss"] do
    cached = value == "hit" == (op == :==)
    where(query, [a], a.was_cached == ^cached)
  end

  defp filter_actions(_, query), do: query

  @doc """
  Roll-up numbers for the Once Builds page: total finalized runs of
  `kind`, share that finalized with a zero exit code, count of runs
  that failed, and average wall-clock duration in milliseconds.
  Matches the shape the Bazel Invocations analytics widgets consume
  so the two pages can share layout without extra mapping.
  """
  def builds_analytics_summary(project_id, opts \\ []) do
    kind = Keyword.get(opts, :kind, "build")

    row =
      Run
      |> where([r], r.project_id == ^project_id and r.finalization == "finalized")
      |> maybe_filter_kind(kind)
      |> select([r], %{
        total: count(r.id),
        failed: sum(fragment("(case when coalesce(?, 0) <> 0 then 1 else 0 end)", r.exit_status)),
        duration_sum: coalesce(sum(r.wall_ms), 0)
      })
      |> Repo.one()

    total = (row && row.total) || 0
    failed = to_integer(row && row.failed)
    duration_sum = to_integer(row && row.duration_sum)
    passed = max(total - failed, 0)

    %{
      total: total,
      failed: failed,
      passed: passed,
      success_rate: if(total > 0, do: passed / total * 100.0),
      avg_duration_ms: if(total > 0, do: div(duration_sum, total), else: 0)
    }
  end

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n) when is_integer(n), do: n

  @doc """
  Cache hit ratio for a project across the last `window` runs. Returns a
  float in [0.0, 1.0] or `nil` when no actions have been recorded.
  """
  def cache_hit_ratio(project_id, window \\ 200) do
    subquery =
      from r in Run,
        where: r.project_id == ^project_id,
        order_by: [desc: r.started_at],
        limit: ^window,
        select: r.id

    result =
      Repo.one(
        from(a in Action,
          where: a.once_run_id in subquery(subquery),
          select: %{total: count(a.id), hits: sum(fragment("(case when ? then 1 else 0 end)", a.was_cached))}
        )
      )

    case result do
      %{total: total, hits: hits} when is_integer(total) and total > 0 ->
        Decimal.to_float(Decimal.div(Decimal.new(hits || 0), Decimal.new(total)))

      _ ->
        nil
    end
  end

  @doc """
  Cache summary for one run. Feeds the Cache Summary tiles on the
  Cache tab. Derived rather than stored so a resend of the same
  event stream still reflects the truth on the actions and
  cache_events tables.
  """
  def cache_summary(%Run{} = run) do
    hits = run.cached_actions || 0
    misses = run.executed_actions || 0
    total = hits + misses

    %{
      hits: hits,
      misses: misses,
      total_lookups: total,
      hit_rate: if(total > 0, do: hits / total * 100.0),
      content_download_bytes: run.cache_bytes_downloaded || 0,
      content_upload_bytes: run.cache_bytes_uploaded || 0,
      content_saved_bytes: run.cache_bytes_saved || 0
    }
  end

  @doc """
  Per-event detail metrics for the Cache tab's Cacheable Actions and
  Content Objects sub-tabs.

  Once's cache activity is currently observable through the
  `once_actions` rows (every action is one cache probe: hit if
  `was_cached`, otherwise miss/write). Until the client emits per-blob
  transfer events we compute the Cacheable Actions metrics directly
  from those rows so the tab is populated for every run.
  """
  def cache_detail_metrics(%Run{} = run) do
    {read_count, read_ms} = action_probe_totals(run, true)
    {write_count, write_ms} = action_probe_totals(run, false)

    download_count =
      Repo.aggregate(from(e in CacheEvent, where: e.once_run_id == ^run.id and e.kind == "download"), :count, :id)

    upload_count =
      Repo.aggregate(from(e in CacheEvent, where: e.once_run_id == ^run.id and e.kind == "upload"), :count, :id)

    %{
      action_read_count: read_count,
      action_read_latency_ms: safe_avg(read_ms, read_count),
      action_write_count: write_count,
      action_write_latency_ms: safe_avg(write_ms, write_count),
      content_download_count: download_count,
      content_upload_count: upload_count,
      content_download_throughput_bytes_per_second: throughput(run.cache_bytes_downloaded || 0, read_ms),
      content_upload_throughput_bytes_per_second: throughput(run.cache_bytes_uploaded || 0, write_ms)
    }
  end

  # Aggregate action probe counts and total wall time for the given
  # `was_cached` bucket. Excludes synthetic `_phase` and materialize
  # plumbing rows so the "reading cache keys" metric reflects real
  # cache-probe traffic, not analysis or filesystem preparation.
  defp action_probe_totals(%Run{} = run, was_cached) do
    row =
      Repo.one(
        from a in Action,
          where:
            a.once_run_id == ^run.id and
              a.was_cached == ^was_cached and
              a.capability != "_phase",
          select: {count(a.id), coalesce(sum(a.duration_ms), 0)}
      )

    case row do
      # `sum/1` on a bigint column comes back as a `Decimal` in
      # Postgrex; coerce to a plain integer so downstream arithmetic
      # (safe_avg, throughput) doesn't blow up on `div/2`.
      {count, %Decimal{} = ms} when is_integer(count) -> {count, Decimal.to_integer(ms)}
      {count, ms} when is_integer(count) -> {count, ms || 0}
      _ -> {0, 0}
    end
  end

  @doc """
  List cache events under a run for the Cache tab.

  Cacheable Actions view: every `once_actions` row is one cache
  probe for its action — hit if `was_cached`, otherwise miss — so we
  synthesize the row set directly from `once_actions`. This gives
  each Once run a populated Cache tab without needing the client to
  emit a separate per-probe event stream. Synthetic `_phase` and
  filesystem-plumbing (`materialize_*`) rows are excluded so the
  view stays scoped to real action cache traffic.

  Content Objects view: still reads `once_cache_events` (only Bazel-
  ingested runs populate that path today; Once runs surface as
  empty).
  """
  def list_cache_events(%Run{} = run, opts \\ []) do
    view = Keyword.get(opts, :view, "actions")

    if view == "content-objects" do
      list_content_object_events(run, opts)
    else
      list_action_cache_probes(run, opts)
    end
  end

  defp list_action_cache_probes(%Run{} = run, opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    search = opts |> Keyword.get(:search, "") |> String.trim()
    outcome = Keyword.get(opts, :outcome)
    sort_by = Keyword.get(opts, :sort_by, "observed")
    sort_order = Keyword.get(opts, :sort_order, "desc")

    from(a in Action, where: a.once_run_id == ^run.id)
    |> exclude_synthetic_rows()
    |> maybe_filter_action_search(search)
    |> maybe_filter_action_outcome(outcome)
    |> apply_action_cache_sort(sort_by, sort_order)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Enum.map(&action_to_cache_probe/1)
  end

  defp list_content_object_events(%Run{} = run, opts) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    search = opts |> Keyword.get(:search, "") |> String.trim()
    outcome = Keyword.get(opts, :outcome)
    sort_by = Keyword.get(opts, :sort_by, "observed")
    sort_order = Keyword.get(opts, :sort_order, "desc")

    # A target owns many actions, so joining on `target_execution_id` alone
    # multiplied every cache event by the number of actions sharing its
    # target. `count_cache_events/2` counts unjoined events, so the count
    # and the page disagreed: rows appeared several times and the events
    # past the first page became unreachable. The identifier is display
    # only, so it comes from one deterministic action per event instead.
    identifier_query =
      from a in Action,
        where:
          a.once_run_id == parent_as(:event).once_run_id and
            a.target_execution_id == parent_as(:event).target_execution_id,
        order_by: [asc: a.capability, asc: a.action_index],
        limit: 1,
        select: a.identifier

    query =
      from e in CacheEvent,
        as: :event,
        where: e.once_run_id == ^run.id,
        select: %{event: e, action_identifier: subquery(identifier_query)}

    query
    |> where([e], e.kind in ["upload", "download"] and not is_nil(e.content_hash))
    |> maybe_filter_search(search)
    |> maybe_filter_outcome(outcome)
    |> apply_cache_sort(sort_by, sort_order)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Enum.map(fn %{event: event, action_identifier: identifier} ->
      Map.put(event, :action_identifier, identifier)
    end)
  end

  # Skip rows that don't represent real cache activity: `_phase` is
  # our synthetic per-target span (analysis, materialize_outputs),
  # not a probe of the action cache. `materialize_%` filesystem
  # actions stay in — for cache-hit-heavy Once runs they *are* the
  # majority of the cache traffic (extract cached blobs into the
  # workspace) so hiding them makes the Cache tab look empty.
  defp exclude_synthetic_rows(query) do
    where(query, [a], a.capability != "_phase")
  end

  defp maybe_filter_action_search(query, ""), do: query

  defp maybe_filter_action_search(query, search) do
    pattern = "%" <> String.replace(search, ~r/[\\%_]/, fn char -> "\\" <> char end) <> "%"
    where(query, [a], ilike(a.target_execution_id, ^pattern) or ilike(a.identifier, ^pattern))
  end

  defp maybe_filter_action_outcome(query, "hit"), do: where(query, [a], a.was_cached == true)
  defp maybe_filter_action_outcome(query, "miss"), do: where(query, [a], a.was_cached == false)
  defp maybe_filter_action_outcome(query, _), do: query

  defp apply_action_cache_sort(query, sort_by, sort_order) do
    direction = if sort_order == "asc", do: :asc_nulls_last, else: :desc_nulls_last

    case sort_by do
      "action" -> order_by(query, [a], [{^direction, a.identifier}, {:asc, a.id}])
      "outcome" -> order_by(query, [a], [{^direction, a.was_cached}, {:asc, a.id}])
      "target" -> order_by(query, [a], [{^direction, a.target_execution_id}, {:asc, a.id}])
      "latency" -> order_by(query, [a], [{^direction, a.duration_ms}, {:asc, a.id}])
      _ -> order_by(query, [a], [{^direction, a.finished_at}, {:asc, a.id}])
    end
  end

  defp cache_key_or_nil(nil), do: nil
  defp cache_key_or_nil(""), do: nil
  defp cache_key_or_nil(hex) when is_binary(hex), do: hex

  # Shape a synthesized action-cache-probe row so it renders in the
  # same LiveView table as native CacheEvent rows.
  defp action_to_cache_probe(%Action{} = action) do
    %{
      id: action.id,
      target_execution_id: action.target_execution_id,
      action_identifier: action.identifier,
      outcome: if(action.was_cached, do: "hit", else: "miss"),
      duration_ms: action.duration_ms || 0,
      observed_at: action.finished_at || action.started_at,
      # `cache_key` is the Bazel-style action digest the client
      # probed against the CAS. Expose it via `content_hash` so the
      # LiveView column mapping stays uniform between synthesized
      # action rows and rows projected from CacheDownload/CacheUpload.
      content_hash: cache_key_or_nil(action.cache_key),
      content_size_bytes: 0
    }
  end

  # Sort keys mirror the Bazel Cache table headers: action/outcome/
  # target/cache_key/size/latency/observed. `action` sorts by the
  # joined once_actions.identifier so the mnemonic groups cluster.
  # `cache_key` sorts by content_hash, `size` by content_size_bytes,
  # `latency` by duration_ms.
  defp apply_cache_sort(query, sort_by, sort_order) do
    direction = if sort_order == "asc", do: :asc_nulls_last, else: :desc_nulls_last

    case sort_by do
      "action" -> order_by(query, [_e, a], [{^direction, a.identifier}, {:asc, _e.id}])
      "outcome" -> order_by(query, [e], [{^direction, e.outcome}, {:asc, e.id}])
      "target" -> order_by(query, [e], [{^direction, e.target_execution_id}, {:asc, e.id}])
      "cache_key" -> order_by(query, [e], [{^direction, e.content_hash}, {:asc, e.id}])
      "size" -> order_by(query, [e], [{^direction, e.content_size_bytes}, {:asc, e.id}])
      "latency" -> order_by(query, [e], [{^direction, e.duration_ms}, {:asc, e.id}])
      _ -> order_by(query, [e], [{^direction, e.observed_at}, {:asc, e.id}])
    end
  end

  def count_cache_events(%Run{} = run, opts \\ []) do
    view = Keyword.get(opts, :view, "actions")
    search = opts |> Keyword.get(:search, "") |> String.trim()
    outcome = Keyword.get(opts, :outcome)

    if view == "content-objects" do
      from(e in CacheEvent, where: e.once_run_id == ^run.id)
      |> where([e], e.kind in ["upload", "download"] and not is_nil(e.content_hash))
      |> maybe_filter_search(search)
      |> maybe_filter_outcome(outcome)
      |> Repo.aggregate(:count, :id)
    else
      from(a in Action, where: a.once_run_id == ^run.id)
      |> exclude_synthetic_rows()
      |> maybe_filter_action_search(search)
      |> maybe_filter_action_outcome(outcome)
      |> Repo.aggregate(:count, :id)
    end
  end

  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    pattern = "%" <> String.replace(search, ~r/[\\%_]/, fn char -> "\\" <> char end) <> "%"

    where(query, [e], ilike(e.target_execution_id, ^pattern) or ilike(e.content_hash, ^pattern))
  end

  defp maybe_filter_outcome(query, outcome) when outcome in ["hit", "miss", "stored", "reused"],
    do: where(query, [e], e.outcome == ^outcome)

  defp maybe_filter_outcome(query, _), do: query

  defp safe_avg(_ms, 0), do: 0
  defp safe_avg(ms, count) when count > 0, do: div(ms, count)

  defp throughput(_bytes, 0), do: 0
  defp throughput(bytes, ms) when ms > 0, do: div(bytes * 1000, ms)

  # ---- Pub/Sub ----------------------------------------------------------

  def subscribe_project(project_id) do
    PubSub.subscribe(@pubsub, project_topic(project_id))
  end

  def subscribe_run(project_id, run_id) do
    PubSub.subscribe(@pubsub, run_topic(project_id, run_id))
  end

  defp broadcast_project(project_id, message) do
    PubSub.broadcast(@pubsub, project_topic(project_id), message)
  end

  defp broadcast_run(%{project_id: project_id, run_id: run_id}, message) do
    PubSub.broadcast(@pubsub, run_topic(project_id, run_id), message)
  end

  defp project_topic(project_id), do: "once:project:#{project_id}"

  # The run id is chosen by the client, so it is scoped by project to keep
  # two projects that happen to pick the same one off each other's topic.
  defp run_topic(project_id, run_id), do: "once:run:#{project_id}:#{run_id}"

  defp maybe_filter_kind(query, nil), do: query
  defp maybe_filter_kind(query, kind), do: where(query, [r], r.kind == ^kind)

  # Preserve millisecond precision at the write boundary so 1000
  # actions completing in the same second don't collapse to the same
  # timestamp. Once's transport carries `at_epoch_ms`, so the finest
  # granularity we can honestly recover is milliseconds.
  defp truncate_datetimes(attrs, keys) do
    Enum.reduce(keys, attrs, fn key, acc ->
      case Map.get(acc, key) do
        %DateTime{} = dt -> Map.put(acc, key, DateTime.truncate(dt, :microsecond))
        _ -> acc
      end
    end)
  end
end
