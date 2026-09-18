defmodule Atlas.Engineering.Errors.IssueCoalescer do
  @moduledoc """
  Coalesces per-issue upserts and counter bumps so the ingest hot path
  can run without any synchronous Postgres round-trip.

  Every observation of an event feeds an in-memory accumulator keyed
  by `{project_id, fingerprint}`; every flush interval the accumulator
  is written back to Postgres as a single multi-row
  `INSERT ... ON CONFLICT DO UPDATE`, folding N events per fingerprint
  into one round-trip. This is the pattern that keeps a runaway loop
  from a single noisy issue (the shape of Tuist's real prod incident)
  from serialising every event on the same row lock.

  ## Semantics

  * `record_event/2` calls `observe/4` — a `GenServer.cast` — and
    returns immediately. Callers no longer need to wait on the issue
    upsert.
  * `event_count` becomes eventually consistent: if the coalescer's
    flush fails, that window's bumps are dropped. ClickHouse still
    holds every event, so the true event history is preserved; the
    Postgres counter is a display convenience that trades exactness
    for throughput. `Atlas.Engineering.Errors.DropAlerter` fires on flush failure
    so the discrepancy is never silent.
  * Regression rules match the previous synchronous code:
      * ignored issues stay ignored
      * resolved issues auto-reopen when the observed
        `MAX(event.timestamp)` for the fingerprint is strictly newer
        than `resolved_at`; older backfilled events do not regress
      * unresolved stays unresolved

  ## Shutdown

  `terminate/2` runs a final flush so pending observations from the
  last window are not lost across a graceful pod restart.
  """

  use GenServer

  import Ecto.Query

  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Repo
  alias Atlas.Slack.API, as: SlackAPI

  require Logger

  @slack_app_key :company

  @flush_interval_ms :timer.seconds(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records an observation of `event` for the issue identified by
  `{project.id, domain_id, fingerprint}` inside the coalescer. Pass
  `:domain_id` in `opts` when the event came in through a domain-scoped
  Data Source Name; omit it (or pass nil) for the project-level DSN.
  Non-blocking.
  """
  def observe(server, %Project{} = project, fingerprint, %SentryEvent{} = event, opts \\ [])
      when is_binary(fingerprint) do
    domain_id = Keyword.get(opts, :domain_id)
    GenServer.cast(server, {:observe, project, domain_id, fingerprint, event})
  end

  @doc """
  Forces an immediate flush of the pending accumulator. Only used in
  tests and by the graceful-shutdown callback.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :flush_interval_ms, @flush_interval_ms)
    timer = Process.send_after(self(), :tick, interval)

    {:ok,
     %{
       # Accumulator keyed by {project_id, domain_id, fingerprint}. A
       # domain_id of nil is the project-level DSN and gets its own
       # bucket, distinct from any domain-scoped observation of the same
       # fingerprint. Value shape documented on `merge_observation/4`.
       accumulator: %{},
       timer: timer,
       interval: interval
     }}
  end

  @impl true
  def handle_cast({:observe, project, domain_id, fingerprint, event}, state) do
    key = {project.id, domain_id, fingerprint}
    entry = Map.get(state.accumulator, key)
    updated = merge_observation(entry, project, domain_id, fingerprint, event)
    {:noreply, %{state | accumulator: Map.put(state.accumulator, key, updated)}}
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state.accumulator)
    timer = Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | accumulator: %{}, timer: timer}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    Process.cancel_timer(state.timer)
    do_flush(state.accumulator)
    timer = Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | accumulator: %{}, timer: timer}}
  end

  @impl true
  def terminate(_reason, %{accumulator: accumulator}) do
    do_flush(accumulator)
  end

  # An accumulator entry holds everything the upsert row needs plus
  # the last-observed environment (used by `Hive.Alerts` rule
  # matching). The most-recently-observed values win for the mutable
  # metadata (title/culprit/level/platform/environment); count is
  # additive; first/last-seen are min/max of every event's timestamp.
  defp merge_observation(nil, project, domain_id, fingerprint, event) do
    ts = event_timestamp(event)

    %{
      id: Issue.deterministic_id(project.id, domain_id, fingerprint),
      project_id: project.id,
      project_name: project.name,
      project_slack_alert_channel: Map.get(project, :slack_alert_channel),
      domain_id: domain_id,
      fingerprint: fingerprint,
      title: SentryEvent.title(event) |> truncate(500),
      culprit: SentryEvent.culprit(event) |> truncate(500),
      level: String.to_atom(event.level),
      platform: event.platform,
      first_seen: ts,
      last_seen: ts,
      count: 1,
      environment: event.environment
    }
  end

  defp merge_observation(entry, _project, _domain_id, _fingerprint, event) do
    ts = event_timestamp(event)

    %{
      entry
      | title: SentryEvent.title(event) |> truncate(500),
        culprit: SentryEvent.culprit(event) |> truncate(500),
        level: String.to_atom(event.level),
        platform: event.platform,
        first_seen: min_dt(entry.first_seen, ts),
        last_seen: max_dt(entry.last_seen, ts),
        count: entry.count + 1,
        environment: event.environment || entry.environment
    }
  end

  # Sentry SDKs commonly send timestamps at millisecond precision
  # (e.g. `~U[2026-09-04 09:12:00.000Z]`), but the `errors_issues`
  # Postgres columns are `:utc_datetime_usec` and demand precision=6.
  # `DateTime.truncate/2` doesn't up-scale, so tag the precision
  # explicitly — the raw microsecond value is unchanged, only the
  # precision label is widened.
  defp event_timestamp(%SentryEvent{timestamp: %DateTime{} = ts}), do: force_usec(ts)
  defp event_timestamp(_), do: DateTime.utc_now() |> force_usec()

  defp force_usec(%DateTime{microsecond: {_, 6}} = dt), do: dt

  defp force_usec(%DateTime{microsecond: {value, _}} = dt), do: %{dt | microsecond: {value, 6}}

  defp min_dt(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
  defp max_dt(a, b), do: if(DateTime.after?(a, b), do: a, else: b)

  defp truncate(nil, _), do: nil
  defp truncate(bin, max) when is_binary(bin), do: String.slice(bin, 0, max)

  defp do_flush(accumulator) when map_size(accumulator) == 0, do: :ok

  defp do_flush(accumulator) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    entries = Map.values(accumulator)
    ids = Enum.map(entries, & &1.id)

    # Snapshot the pre-flush state so `Hive.Alerts.evaluate_error_issue/3`
    # can tell a regression (resolved → unresolved) apart from a plain
    # repeat. New fingerprints show up here as empty structs so the
    # alert evaluator still gets a `before` argument.
    before_by_id = snapshot_before(ids)

    rows = Enum.map(entries, &row_for_upsert(&1, now))

    try do
      {_inserted, after_issues} =
        Repo.insert_all(
          Issue,
          rows,
          on_conflict: on_conflict_query(),
          conflict_target: [:project_id, :domain_id, :fingerprint],
          returning: true
        )

      evaluate_alerts_for(after_issues, entries, before_by_id)
      length(after_issues)
    rescue
      error ->
        total_events = Enum.reduce(entries, 0, &(&2 + &1.count))

        Logger.error(
          "issue_coalescer: flush failed for #{map_size(accumulator)} fingerprint(s) " <>
            "(#{total_events} event bumps dropped): #{Exception.message(error)}"
        )

        # Follow-up: wire alerting for coalescer flush failures.
        Logger.warning(
          "issue_coalescer: alert #{inspect({:issue_coalescer_flush_failed, Exception.message(error)})} fingerprints=#{map_size(accumulator)} events=#{total_events}"
        )

        0
    end
  end

  defp snapshot_before(ids) do
    Issue
    |> where([i], i.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp row_for_upsert(entry, now) do
    %{
      id: entry.id,
      project_id: entry.project_id,
      domain_id: entry.domain_id,
      fingerprint: entry.fingerprint,
      title: entry.title,
      culprit: entry.culprit,
      level: entry.level,
      platform: entry.platform,
      status: :unresolved,
      first_seen: entry.first_seen,
      last_seen: entry.last_seen,
      event_count: entry.count,
      resolved_at: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  # Fires one Slack alert per touched fingerprint that is either brand
  # new or a regression (resolved → unresolved). Failures inside the
  # alerts pipeline must not fail the coalescer flush — the event is
  # already recorded — so each call is wrapped in a rescue that logs
  # and continues.
  #
  # The flush-window coalescing itself is the rate-limiter: multiple
  # observations of the same fingerprint inside a window collapse to
  # one entry and, at most, one alert. Repeats within a still-
  # unresolved issue produce no alert; only transitions do.
  defp evaluate_alerts_for(after_issues, entries, before_by_id) do
    entry_by_id = Map.new(entries, &{&1.id, &1})

    Enum.each(after_issues, fn %Issue{id: id} = issue ->
      entry = Map.fetch!(entry_by_id, id)
      before = Map.get(before_by_id, id)

      reason = alert_reason(before, issue)

      if reason do
        try do
          deliver_slack_alert(issue, entry, reason)
        rescue
          err ->
            Logger.warning("issue_coalescer: alert delivery failed: #{inspect(err)}")
        end
      end
    end)
  end

  defp alert_reason(nil, %Issue{}), do: :new_issue

  defp alert_reason(%{status: :resolved}, %Issue{status: :unresolved}), do: :regression

  defp alert_reason(_before, _issue), do: nil

  defp deliver_slack_alert(%Issue{} = issue, entry, reason) do
    case resolve_channel(entry) do
      {:ok, channel_id} ->
        fallback = fallback_text(reason, issue, entry)
        blocks = alert_blocks(reason, issue, entry)

        case SlackAPI.post_message(@slack_app_key, channel_id, fallback, blocks) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("issue_coalescer: slack post failed for issue=#{issue.id}: #{inspect(reason)}")

            :ok
        end

      :no_channel ->
        Logger.warning(
          "issue_coalescer: no Slack channel configured for project=#{inspect(Map.get(entry, :project_name))} " <>
            "(project_id=#{entry.project_id}); dropping alert for issue=#{issue.id}"
        )

        :ok
    end
  end

  defp resolve_channel(entry) do
    per_project = Map.get(entry, :project_slack_alert_channel)
    default = Application.get_env(:atlas, :default_alert_slack_channel)

    cond do
      is_binary(per_project) and per_project != "" -> {:ok, per_project}
      is_binary(default) and default != "" -> {:ok, default}
      true -> :no_channel
    end
  end

  defp fallback_text(reason, %Issue{} = issue, entry) do
    env_part =
      case entry.environment do
        env when is_binary(env) and env != "" -> " · #{env}"
        _ -> ""
      end

    "#{reason_emoji(reason)} #{reason_label(reason)} · #{level_label(issue.level)}#{env_part} · " <>
      single_line(issue.title || "")
  end

  defp alert_blocks(reason, %Issue{} = issue, entry) do
    header_text = "#{reason_emoji(reason)} #{reason_label(reason)}"

    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => truncate(header_text, 150), "emoji" => true}
      },
      title_block(issue),
      severity_fields_block(issue, entry.environment),
      %{"type" => "divider"},
      context_block(issue, entry),
      actions_block(issue)
    ]
  end

  defp title_block(%Issue{} = issue) do
    url = issue_url(issue)

    subtitle =
      case culprit_line(issue) do
        nil -> ""
        line -> "\n`#{escape(line)}`"
      end

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => "*<#{url}|#{escape(truncate(single_line(issue.title || ""), 200))}>*#{subtitle}"
      }
    }
  end

  defp severity_fields_block(%Issue{} = issue, environment) do
    %{
      "type" => "section",
      "fields" => [
        field("Level", level_field(issue.level)),
        field("Environment", environment_field(environment)),
        field("Events", format_count(issue.event_count)),
        field("Last seen", relative_time(issue.last_seen)),
        field("First seen", relative_time(issue.first_seen)),
        field("Status", status_field(issue.status))
      ]
    }
  end

  defp field(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}*\n#{value}"}
  end

  defp context_block(%Issue{} = issue, entry) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" => "Project: *#{escape(project_name(entry))}*"
        },
        %{
          "type" => "mrkdwn",
          "text" => "Fingerprint: `#{short_fingerprint(issue.fingerprint)}`"
        }
      ]
    }
  end

  defp actions_block(%Issue{} = issue) do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => "Open issue", "emoji" => true},
          "url" => issue_url(issue),
          "style" => "primary"
        }
      ]
    }
  end

  defp reason_emoji(:new_issue), do: "🆕"
  defp reason_emoji(:regression), do: "🔁"
  defp reason_emoji(_), do: "⚠️"

  defp reason_label(:new_issue), do: "New issue"
  defp reason_label(:regression), do: "Regression"
  defp reason_label(other) when is_atom(other), do: Atom.to_string(other)
  defp reason_label(other), do: to_string(other)

  defp level_field(:fatal), do: "🟣 fatal"
  defp level_field(:error), do: "🔴 error"
  defp level_field(:warning), do: "🟡 warning"
  defp level_field(:info), do: "🔵 info"
  defp level_field(:debug), do: "⚪ debug"
  defp level_field(nil), do: "—"
  defp level_field(other), do: to_string(other)

  defp level_label(nil), do: "unknown"
  defp level_label(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp level_label(other), do: to_string(other)

  defp status_field(:resolved), do: "resolved"
  defp status_field(:ignored), do: "ignored"
  defp status_field(:unresolved), do: "unresolved"
  defp status_field(nil), do: "—"
  defp status_field(other), do: to_string(other)

  defp environment_field(nil), do: "—"
  defp environment_field(""), do: "—"

  defp environment_field(env) when is_binary(env) do
    if env in ~w(production prod live) do
      "*`#{escape(env)}`*"
    else
      "`#{escape(env)}`"
    end
  end

  defp environment_field(other), do: to_string(other)

  defp format_count(nil), do: "0"
  defp format_count(n) when is_integer(n) and n >= 1_000_000, do: "#{div(n, 1_000_000)}M"
  defp format_count(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_count(n) when is_integer(n), do: Integer.to_string(n)
  defp format_count(other), do: to_string(other)

  defp relative_time(nil), do: "—"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp culprit_line(%Issue{culprit: culprit}) when is_binary(culprit) and culprit != "" do
    truncate(single_line(culprit), 200)
  end

  defp culprit_line(_), do: nil

  defp single_line(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp single_line(other), do: to_string(other)

  defp project_name(%{project_name: name}) when is_binary(name) and name != "", do: name
  defp project_name(_), do: "unknown"

  defp issue_url(%Issue{id: id}) do
    AtlasWeb.Endpoint.url() <> "/engineering/errors/#{id}"
  end

  defp short_fingerprint(fp) when is_binary(fp) and byte_size(fp) >= 8, do: String.slice(fp, 0, 8)
  defp short_fingerprint(_), do: "—"

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # `insert_all` with ON CONFLICT DO UPDATE. The counter is added to
  # the existing value, first/last-seen are folded via LEAST/GREATEST,
  # the mutable metadata is replaced, and the regression rules are
  # applied via SQL CASE — reopen only if this batch's max timestamp
  # is strictly newer than `resolved_at`.
  defp on_conflict_query do
    from(existing in Issue,
      update: [
        set: [
          event_count: fragment("? + EXCLUDED.event_count", existing.event_count),
          first_seen: fragment("LEAST(?, EXCLUDED.first_seen)", existing.first_seen),
          last_seen: fragment("GREATEST(?, EXCLUDED.last_seen)", existing.last_seen),
          title: fragment("EXCLUDED.title"),
          culprit: fragment("EXCLUDED.culprit"),
          level: fragment("EXCLUDED.level"),
          platform: fragment("EXCLUDED.platform"),
          status:
            fragment(
              """
              CASE
                WHEN ? = 'ignored' THEN ?
                WHEN ? = 'resolved' AND ? IS NOT NULL AND EXCLUDED.last_seen > ? THEN ?
                ELSE ?
              END
              """,
              existing.status,
              "ignored",
              existing.status,
              existing.resolved_at,
              existing.resolved_at,
              "unresolved",
              existing.status
            ),
          resolved_at:
            fragment(
              """
              CASE
                WHEN ? = 'resolved' AND ? IS NOT NULL AND EXCLUDED.last_seen > ? THEN NULL
                ELSE ?
              END
              """,
              existing.status,
              existing.resolved_at,
              existing.resolved_at,
              existing.resolved_at
            ),
          updated_at: fragment("CURRENT_TIMESTAMP")
        ]
      ]
    )
  end
end
