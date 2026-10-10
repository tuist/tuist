defmodule Tuist.Automations.Builds do
  @moduledoc "Build automation evaluation and durable cache-key findings."
  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Builds.CacheKeyMonitor
  alias Tuist.Automations.Builds.Finding
  alias Tuist.Projects
  alias Tuist.Repo

  require Logger

  @monitor_type "cache_key_consistency"
  @scan_budget_ms 120_000

  def monitor?(%{monitor_type: @monitor_type}), do: true
  def monitor?(_), do: false

  def supported?(%{build_system: build_system}), do: CacheKeyMonitor.sources(build_system) != []

  def list_findings(alert_id, before_id \\ nil) do
    query = from(f in Finding, where: f.alert_id == ^alert_id, order_by: [desc: f.id], limit: 21)
    query = if before_id, do: where(query, [f], f.id < ^before_id), else: query
    Repo.all(query)
  end

  def evaluate(alert) do
    # Serialize external delivery per rule without holding a row lock across Slack.
    Repo.checkout(
      fn ->
        with_lock("build-automation-scans", fn ->
          with_lock("build-automation:#{alert.id}", fn ->
            evaluate_active(alert.id)
          end)
        end)
      end,
      timeout: :infinity
    )
  end

  defp evaluate_active(id) do
    case active_alert(id) do
      {:ok, current} ->
        project = Projects.get_project_by_id(current.project_id)
        sources = CacheKeyMonitor.sources(project.build_system)
        if baseline_ready?(current, sources), do: notify_pending(current)
        deadline = System.monotonic_time(:millisecond) + @scan_budget_ms
        Enum.each(sources, fn source -> evaluate_source(current, source, deadline) end)
        finish_evaluation(id, sources)

      :inactive ->
        :ok
    end
  end

  defp finish_evaluation(id, sources) do
    case active_alert(id) do
      {:ok, refreshed} ->
        delivery = if baseline_ready?(refreshed, sources), do: notify_pending(refreshed), else: :ok

        incomplete =
          not baseline_ready?(refreshed, sources) or
            Enum.any?(sources, &Map.has_key?(refreshed.build_scan_state[&1] || %{}, "until"))

        if delivery == :ok and incomplete, do: {:snooze, Enum.random(1..5)}, else: delivery

      :inactive ->
        :ok
    end
  end

  defp with_lock(lock, callback) do
    case Repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [lock]).rows do
      [[true]] ->
        try do
          callback.()
        after
          Repo.query!("SELECT pg_advisory_unlock(hashtextextended($1, 0))", [lock])
        end

      [[false]] ->
        {:snooze, if(lock == "build-automation-scans", do: Enum.random(1..5), else: 30)}
    end
  end

  defp baseline_ready?(alert, sources),
    do: Enum.all?(sources, &(not is_nil(get_in(alert.build_scan_state, [&1, "full_completed_at"]))))

  defp active_alert(id) do
    case Automations.get_alert(id) do
      {:ok, %{enabled: true} = alert} -> if monitor?(alert), do: {:ok, alert}, else: :inactive
      _ -> :inactive
    end
  end

  defp evaluate_source(alert, source, deadline) do
    with {:ok, current} <- active_alert(alert.id),
         true <- System.monotonic_time(:millisecond) < deadline do
      now = DateTime.utc_now()
      state = scan_state(current.build_scan_state[source] || %{}, now)
      until = datetime(state["until"])
      cutoff = until |> DateTime.add(-30, :day) |> DateTime.truncate(:second)

      commits =
        CacheKeyMonitor.commits(current.project_id, source, state["cursor"], cutoff, datetime(state["since"]), until)

      commits =
        if state["active_commit"],
          do: [state["active_commit"] | Enum.reject(commits, &(&1 == state["active_commit"]))],
          else: commits

      save_scan(current.id, source, state)

      {processed, state} =
        commits
        |> Enum.take(10)
        |> Enum.reduce_while({0, state}, fn commit, {count, checkpoint} ->
          cursor = if checkpoint["active_commit"] == commit, do: checkpoint["identity_cursor"] || "", else: ""

          case evaluate_commit(current, source, commit, cursor, checkpoint, %{
                 cutoff: cutoff,
                 until: until,
                 deadline: deadline
               }) do
            {:complete, checkpoint} ->
              checkpoint = checkpoint |> Map.drop(["active_commit", "identity_cursor"]) |> Map.put("cursor", commit)
              save_scan(current.id, source, checkpoint)
              {:cont, {count + 1, checkpoint}}

            {:paused, checkpoint} ->
              {:halt, {count, checkpoint}}
          end
        end)

      if processed == length(commits) do
        completed = Map.drop(state, ["until", "since", "cursor", "full", "active_commit", "identity_cursor"])
        completed = Map.put(completed, "completed_at", state["until"])
        completed = if state["full"], do: Map.put(completed, "full_completed_at", state["until"]), else: completed
        save_scan(current.id, source, completed)
      end
    end

    :ok
  end

  defp scan_state(%{"until" => _} = state, _now), do: state

  defp scan_state(state, now) do
    full = is_nil(state["full_completed_at"]) or DateTime.diff(now, datetime(state["full_completed_at"])) >= 86_400
    cutoff = DateTime.add(now, -30, :day)
    since = if full, do: cutoff, else: DateTime.add(datetime(state["completed_at"]), -3600, :second)

    state = if full, do: Map.put(state, "skipped_commits", 0), else: state

    Map.merge(state, %{
      "until" => DateTime.to_iso8601(now),
      "since" => DateTime.to_iso8601(since),
      "cursor" => "",
      "full" => full
    })
  end

  defp datetime(value) do
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    datetime
  end

  defp save_scan(alert_id, source, state) do
    # Update one source atomically without overwriting another source's checkpoint.
    Repo.query!(
      "UPDATE automation_alerts SET build_scan_state = jsonb_set(build_scan_state, ARRAY[$2]::text[], $3::jsonb) WHERE id = $1::uuid",
      [Ecto.UUID.dump!(alert_id), source, state]
    )
  end

  defp evaluate_commit(alert, source, commit, cursor, state, %{cutoff: cutoff, until: until, deadline: deadline} = window) do
    if System.monotonic_time(:millisecond) < deadline and match?({:ok, _}, active_alert(alert.id)) do
      findings = CacheKeyMonitor.page(alert.project_id, source, cursor, cutoff, commit: commit, until: until)
      persist(alert, findings)

      if length(findings) == CacheKeyMonitor.page_size() do
        cursor = List.last(findings).unit_key
        checkpoint = Map.merge(state, %{"active_commit" => commit, "identity_cursor" => cursor})
        save_scan(alert.id, source, checkpoint)
        evaluate_commit(alert, source, commit, cursor, checkpoint, window)
      else
        {:complete, state}
      end
    else
      {:paused, state}
    end
  rescue
    error in Ch.Error ->
      if error.code in [159, 241] do
        Logger.warning(
          "Build automation #{alert.id} skipped a resource-limited #{source} comparison (#{error.code}); the next full sweep retries it"
        )

        {:complete, Map.update(state, "skipped_commits", 1, &(&1 + 1))}
      else
        reraise error, __STACKTRACE__
      end
  end

  def persist(alert, findings) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(findings, fn finding ->
        %{
          id: UUIDv7.generate(),
          alert_id: alert.id,
          source: finding.source,
          unit_id: Base.encode16(:crypto.hash(:sha256, "v1:" <> finding.unit_key), case: :lower),
          evidence: Map.new(finding, fn {key, value} -> {to_string(key), value} end),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Finding, rows, on_conflict: :nothing, conflict_target: [:alert_id, :source, :unit_id])
  end

  def notify_pending(alert) do
    case active_alert(alert.id) do
      {:ok, current} ->
        batch = UUIDv7.generate()
        pending = from(f in Finding, where: f.alert_id == ^current.id and is_nil(f.notified_at))
        {count, _} = Repo.update_all(pending, set: [notification_batch: batch])

        if count > 0 do
          samples =
            Repo.all(
              from(f in Finding,
                where: f.alert_id == ^current.id and f.notification_batch == ^batch,
                order_by: f.id,
                limit: 3
              )
            )

          deliver_batch(current, samples, count, batch)
        else
          :ok
        end

      :inactive ->
        :ok
    end
  end

  defp deliver_batch(current, samples, count, batch) do
    case ActionExecutor.execute_actions(current.trigger_actions, current, %{
           type: :build_findings,
           id: current.id,
           findings: samples,
           finding_count: count
         }) do
      :ok ->
        Repo.update_all(from(f in Finding, where: f.alert_id == ^current.id and f.notification_batch == ^batch),
          set: [notified_at: DateTime.utc_now(:second)]
        )

        :ok

      {:error, reason} = error ->
        if permanent_delivery_error?(reason) do
          Logger.warning("Build automation #{current.id} Slack destination needs attention; findings remain pending")
          :ok
        else
          error
        end
    end
  end

  defp permanent_delivery_error?(reason)
       when reason in [:slack_not_configured, :webhook_revoked, :invalid_ciphertext, :invalid_webhook_url], do: true

  defp permanent_delivery_error?({:bad_request, _, _, _}), do: true

  defp permanent_delivery_error?(reason)
       when reason in [
              "invalid_auth",
              "token_revoked",
              "account_inactive",
              "channel_not_found",
              "is_archived",
              "not_in_channel"
            ], do: true

  defp permanent_delivery_error?(_), do: false

  def run_path("bazel", run_id), do: "/builds/invocations/#{URI.encode(run_id, &URI.char_unreserved?/1)}"
  def run_path("once", run_id), do: "/once/runs/#{URI.encode(run_id, &URI.char_unreserved?/1)}"
  def run_path("xcode_module", run_id), do: "/runs/#{URI.encode(run_id, &URI.char_unreserved?/1)}"
  def run_path(_, run_id), do: "/builds/build-runs/#{URI.encode(run_id, &URI.char_unreserved?/1)}"

  def source_label("gradle"), do: "Gradle"
  def source_label("bazel"), do: "Bazel"
  def source_label("once"), do: "Once"
  def source_label("xcode_module"), do: "Xcode module cache"
  def source_label("xcode_compilation"), do: "Xcode compilation cache"
end
