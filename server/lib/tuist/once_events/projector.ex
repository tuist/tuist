defmodule Tuist.OnceEvents.Projector do
  @moduledoc """
  Translates `once.events.v1` proto events into `Tuist.OnceEvents` writes.

  One projector call per event, in the sequence the bidi stream delivered
  them. Each write is idempotent so a resend after a stream break replays
  cleanly.
  """
  alias Once.Events.V1.ActionCompleted
  alias Once.Events.V1.CacheDownload
  alias Once.Events.V1.CacheStoreReused
  alias Once.Events.V1.CacheUpload
  alias Once.Events.V1.RunCompleted
  alias Once.Events.V1.RunEvent
  alias Once.Events.V1.RunStarted
  alias Once.Events.V1.SystemSampled
  alias Once.Events.V1.TargetResult
  alias Once.Events.V1.TestCaseCompleted
  alias Once.Events.V1.TestCaseResult
  alias Once.Events.V1.TestSuiteCompleted
  alias Once.Events.V1.TestSuiteStarted
  alias Tuist.OnceEvents

  @doc """
  Project one `RunEvent` under the resolved project. Returns `:ok` on any
  outcome (including a benign skip); the transport signals REJECTED_INVALID
  when it cannot even parse the frame.
  """
  def project(%RunEvent{payload: {:run_started, %RunStarted{} = started}} = ev, project_id, run_id) do
    OnceEvents.upsert_run(%{
      run_id: run_id,
      project_id: project_id,
      once_version: started.once_version,
      protocol_version: started.protocol_version,
      host_class: started.host_class,
      git_rev: started.git_rev,
      git_dirty: started.git_dirty,
      argv_normalized: argv_to_map(started.argv_normalized),
      argv_hash_key_id: started.argv_hash_key_id,
      safe_literal_allowlist_version: started.safe_literal_allowlist_version,
      cwd_relative: started.cwd_relative,
      env_fingerprint: started.env_fingerprint,
      command_display: render_argv(started.argv_normalized),
      kind: infer_kind(started),
      started_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
    })

    :ok
  end

  def project(%RunEvent{payload: {:action_completed, %ActionCompleted{} = action}} = ev, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      # The client sends `start_at_epoch_ms` under the RFC 0008.v2
      # extension. Falls back to `envelope.epoch_ms - duration_ms`
      # for older clients, which collapses many actions into the same
      # millisecond bucket but keeps the run projectable.
      start_ms =
        cond do
          is_integer(action.start_at_epoch_ms) and action.start_at_epoch_ms > 0 ->
            action.start_at_epoch_ms

          true ->
            ev.epoch_ms - (action.duration_ms || 0)
        end

      OnceEvents.ingest_action(run, %{
        target_execution_id: safe_string(action.target_execution_id),
        capability: safe_string(action.capability, "build"),
        action_index: action.action_index || 0,
        identifier: nil_if_empty(action.identifier),
        result: target_result(action.result),
        was_cached: action.was_cached,
        exit_code: action.exit_code || 0,
        duration_ms: action.duration_ms || 0,
        worker_id: safe_string(action.worker_id),
        prepare_ms: action.prepare_ms || 0,
        execute_ms: action.execute_ms || 0,
        cache_key: safe_string(action.cache_key),
        started_at: from_epoch_ms(start_ms),
        finished_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(%RunEvent{payload: {:run_completed, %RunCompleted{} = completed}}, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      OnceEvents.finalize_run(run, %{
        finalization: "finalized",
        exit_status: run_result_exit(completed.result),
        cancellation_reason: nil_if_empty(completed.cancellation_reason),
        wall_ms: completed.wall_ms,
        finalized_at: DateTime.utc_now()
      })
    end

    :ok
  end

  def project(%RunEvent{payload: {:run_finalizing, _}}, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      OnceEvents.finalize_run(run, %{finalization: "finalizing"})
    end

    :ok
  end

  def project(%RunEvent{payload: {:cache_upload, %CacheUpload{} = up}} = ev, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      OnceEvents.ingest_cache_event(run, %{
        kind: "upload",
        target_execution_id: safe_string(up.target_execution_id),
        cache_decision_id: nil_if_empty(up.cache_decision_id),
        tier: nil_if_empty(up.tier),
        category: nil_if_empty(up.kind),
        content_hash: content_ref_hash(up.content),
        content_size_bytes: content_ref_size(up.content),
        bytes_transferred: up.bytes_transferred || 0,
        duration_ms: up.duration_ms || 0,
        outcome: "stored",
        observed_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(%RunEvent{payload: {:cache_download, %CacheDownload{} = down}} = ev, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      OnceEvents.ingest_cache_event(run, %{
        kind: "download",
        target_execution_id: safe_string(down.target_execution_id),
        cache_decision_id: nil_if_empty(down.cache_decision_id),
        tier: nil_if_empty(down.tier),
        category: nil_if_empty(down.kind),
        content_hash: content_ref_hash(down.content),
        content_size_bytes: content_ref_size(down.content),
        bytes_transferred: down.bytes_transferred || 0,
        duration_ms: down.duration_ms || 0,
        outcome: "hit",
        observed_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(%RunEvent{payload: {:cache_store_reused, %CacheStoreReused{} = reused}} = ev, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      OnceEvents.ingest_cache_event(run, %{
        kind: "reused",
        target_execution_id: safe_string(reused.target_execution_id),
        cache_decision_id: nil_if_empty(reused.cache_decision_id),
        tier: nil_if_empty(reused.tier),
        category: nil_if_empty(reused.kind),
        content_hash: content_ref_hash(reused.content),
        content_size_bytes: content_ref_size(reused.content),
        bytes_transferred: 0,
        duration_ms: 0,
        outcome: "reused",
        observed_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(
        %RunEvent{payload: {:test_suite_started, %TestSuiteStarted{} = started}} = ev,
        project_id,
        run_id
      ) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      OnceEvents.ingest_test_suite_run(run, %{
        target_execution_id: safe_string(started.target_execution_id),
        suite_id: nil_if_empty(started.suite_id) || safe_string(started.target_execution_id),
        planned_case_count: started.planned_case_count,
        started_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(
        %RunEvent{payload: {:test_suite_completed, %TestSuiteCompleted{} = completed}} = ev,
        project_id,
        run_id
      ) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      totals = completed.totals || %{}

      OnceEvents.ingest_test_suite_run(run, %{
        target_execution_id: safe_string(completed.target_execution_id),
        suite_id: nil_if_empty(completed.suite_id) || safe_string(completed.target_execution_id),
        total_cases:
          Map.get(totals, :passed, 0) + Map.get(totals, :failed, 0) +
            Map.get(totals, :skipped, 0) + Map.get(totals, :errored, 0) +
            Map.get(totals, :timed_out, 0) + Map.get(totals, :cancelled, 0),
        passed_cases: Map.get(totals, :passed, 0),
        failed_cases: Map.get(totals, :failed, 0),
        skipped_cases: Map.get(totals, :skipped, 0),
        errored_cases: Map.get(totals, :errored, 0),
        timed_out_cases: Map.get(totals, :timed_out, 0),
        cancelled_cases: Map.get(totals, :cancelled, 0),
        finished_at: from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(
        %RunEvent{payload: {:test_case_completed, %TestCaseCompleted{} = completed}} = ev,
        project_id,
        run_id
      ) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      # `TestCaseCompleted` carries its own identity so a retrospective
      # report never needs a matching `TestCaseStarted`. The legacy
      # `test_case_execution_id` (target#case#attempt) is still there
      # for older clients, so we split it as the fallback path.
      composite = safe_string(completed.test_case_execution_id)
      {target_execution_id, composite_case_id} = split_execution_id(composite)

      case_id =
        nil_if_empty(completed.case_id) ||
          composite_case_id ||
          ""

      suite_id =
        nil_if_empty(completed.suite_id) ||
          target_execution_id

      target_execution_id = nil_if_empty(target_execution_id) || safe_string(suite_id)

      duration_ms = observed_or_declared_duration(completed)
      finished_at = from_epoch_ms(ev.epoch_ms) || DateTime.utc_now()

      started_at =
        if duration_ms > 0 do
          DateTime.add(finished_at, -duration_ms, :millisecond)
        else
          nil
        end

      OnceEvents.ingest_test_case_run(run, %{
        target_execution_id: safe_string(target_execution_id),
        suite_id: safe_string(suite_id),
        case_id: case_id,
        name: safe_string(completed.name) |> non_empty_or(case_id),
        attempt: max(completed.attempt || 1, 1),
        result: test_case_result(completed.result),
        duration_ms: duration_ms,
        failure_message: extract_failure_message(completed.failure),
        started_at: started_at,
        finished_at: finished_at
      })
    end

    :ok
  end

  defp split_execution_id(id) when is_binary(id) do
    case String.split(id, "#", parts: 3) do
      [target, case_id, _attempt] -> {target, case_id}
      [target, case_id] -> {target, case_id}
      _ -> {"", nil}
    end
  end

  defp split_execution_id(_), do: {"", nil}

  defp observed_or_declared_duration(%TestCaseCompleted{} = completed) do
    case completed.observed_duration_ms do
      value when is_integer(value) and value > 0 -> value
      _ -> completed.duration_ms || 0
    end
  end

  def project(%RunEvent{payload: {:system_sampled, %SystemSampled{} = sample}} = ev, project_id, run_id) do
    with %{} = run <- OnceEvents.get_run(project_id, run_id) do
      at_ms =
        cond do
          is_integer(sample.at_epoch_ms) and sample.at_epoch_ms > 0 -> sample.at_epoch_ms
          is_integer(ev.epoch_ms) and ev.epoch_ms > 0 -> ev.epoch_ms
          true -> System.system_time(:millisecond)
        end

      OnceEvents.ingest_system_sample(run, %{
        at_ms: at_ms,
        cpu_percent: safe_float(sample.cpu_percent),
        memory_bytes: sample.memory_bytes || 0,
        network_in_bytes: sample.network_in_bytes_per_second || 0,
        network_out_bytes: sample.network_out_bytes_per_second || 0,
        observed_at: from_epoch_ms(at_ms) || DateTime.utc_now()
      })
    end

    :ok
  end

  def project(_other, _project_id, _run_id), do: :ok

  defp safe_float(nil), do: 0.0
  defp safe_float(n) when is_number(n), do: n / 1

  # ---- Helpers ----------------------------------------------------------

  @target_result_succeeded TargetResult.value(:TARGET_RESULT_SUCCEEDED)
  @target_result_failed TargetResult.value(:TARGET_RESULT_FAILED)
  @target_result_skipped TargetResult.value(:TARGET_RESULT_SKIPPED)
  @target_result_cancelled TargetResult.value(:TARGET_RESULT_CANCELLED)
  @target_result_timed_out TargetResult.value(:TARGET_RESULT_TIMED_OUT)
  @target_result_infra_error TargetResult.value(:TARGET_RESULT_INFRASTRUCTURE_ERROR)

  defp target_result(@target_result_succeeded), do: "succeeded"
  defp target_result(@target_result_failed), do: "failed"
  defp target_result(@target_result_skipped), do: "skipped"
  defp target_result(@target_result_cancelled), do: "cancelled"
  defp target_result(@target_result_timed_out), do: "timed_out"
  defp target_result(@target_result_infra_error), do: "infrastructure_error"
  defp target_result(:TARGET_RESULT_SUCCEEDED), do: "succeeded"
  defp target_result(:TARGET_RESULT_FAILED), do: "failed"
  defp target_result(:TARGET_RESULT_SKIPPED), do: "skipped"
  defp target_result(:TARGET_RESULT_CANCELLED), do: "cancelled"
  defp target_result(:TARGET_RESULT_TIMED_OUT), do: "timed_out"
  defp target_result(:TARGET_RESULT_INFRASTRUCTURE_ERROR), do: "infrastructure_error"
  defp target_result(_), do: "succeeded"

  defp run_result_exit(result) when result in [1, :RUN_RESULT_SUCCEEDED], do: 0
  defp run_result_exit(_), do: 1

  defp from_epoch_ms(ms) when is_integer(ms) and ms > 0 do
    case DateTime.from_unix(ms, :millisecond) do
      # `from_unix(:millisecond)` gives `{value, 3}` precision.
      # Bump to 6 so `:utc_datetime_usec` fields accept it — the
      # underlying microseconds are what we ultimately want to
      # store (millisecond value × 1000 microseconds).
      # `DateTime.from_unix/2` at :millisecond precision already stores
      # the sub-second value in *microseconds* (e.g. 178 ms → 178_000 μs)
      # tagged as precision 3. All we need is to relabel it as
      # precision 6 so the :utc_datetime_usec schema accepts it —
      # multiplying by 1000 blew past the 999_999 μs cap.
      {:ok, dt} -> %{dt | microsecond: {elem(dt.microsecond, 0), 6}}
      _ -> nil
    end
  end

  defp from_epoch_ms(_), do: nil

  defp safe_string(nil), do: ""
  defp safe_string(""), do: ""
  defp safe_string(binary) when is_binary(binary), do: String.slice(binary, 0, 512)
  defp safe_string(_), do: ""

  defp nil_if_empty(nil), do: nil
  defp nil_if_empty(""), do: nil
  defp nil_if_empty(binary) when is_binary(binary), do: binary
  defp nil_if_empty(_), do: nil

  defp non_empty_or("", fallback), do: fallback || ""
  defp non_empty_or(nil, fallback), do: fallback || ""
  defp non_empty_or(binary, _), do: binary

  @test_case_passed TestCaseResult.value(:TEST_CASE_RESULT_PASSED)
  @test_case_failed TestCaseResult.value(:TEST_CASE_RESULT_FAILED)
  @test_case_skipped TestCaseResult.value(:TEST_CASE_RESULT_SKIPPED)
  @test_case_errored TestCaseResult.value(:TEST_CASE_RESULT_ERRORED)
  @test_case_timed_out TestCaseResult.value(:TEST_CASE_RESULT_TIMED_OUT)
  @test_case_cancelled TestCaseResult.value(:TEST_CASE_RESULT_CANCELLED)

  defp test_case_result(@test_case_passed), do: "passed"
  defp test_case_result(@test_case_failed), do: "failed"
  defp test_case_result(@test_case_skipped), do: "skipped"
  defp test_case_result(@test_case_errored), do: "errored"
  defp test_case_result(@test_case_timed_out), do: "timed_out"
  defp test_case_result(@test_case_cancelled), do: "cancelled"
  defp test_case_result(:TEST_CASE_RESULT_PASSED), do: "passed"
  defp test_case_result(:TEST_CASE_RESULT_FAILED), do: "failed"
  defp test_case_result(:TEST_CASE_RESULT_SKIPPED), do: "skipped"
  defp test_case_result(:TEST_CASE_RESULT_ERRORED), do: "errored"
  defp test_case_result(:TEST_CASE_RESULT_TIMED_OUT), do: "timed_out"
  defp test_case_result(:TEST_CASE_RESULT_CANCELLED), do: "cancelled"
  defp test_case_result(_), do: "passed"

  defp extract_failure_message(nil), do: nil

  defp extract_failure_message(%{message: msg}) when is_binary(msg) and msg != "",
    do: String.slice(msg, 0, 4000)

  defp extract_failure_message(_), do: nil

  defp safe_string(v, default) do
    case safe_string(v) do
      "" -> default
      s -> s
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(nil), do: nil
  defp nil_if_empty(s) when is_binary(s), do: s

  # Serialize the argv tokens into a JSON-friendly shape so the dashboard
  # can render them without proto knowledge.
  defp argv_to_map(tokens) when is_list(tokens) do
    %{
      "tokens" =>
        Enum.map(tokens, fn token ->
          case token.token do
            {:safe_literal, value} ->
              %{"kind" => "safe_literal", "value" => value}

            {:flag_key, key} ->
              %{"kind" => "flag_key", "key" => key}

            {:named_value, %{key: key, value_shape_hash: hash}} ->
              %{"kind" => "named_value", "key" => key, "value_shape_hash" => hash}

            {:opaque_value_hash, hash} ->
              %{"kind" => "opaque", "value_shape_hash" => hash}

            _ ->
              %{"kind" => "unknown"}
          end
        end)
    }
  end

  defp argv_to_map(_), do: %{"tokens" => []}

  # Render a display-only command line from safe literals; opaque tokens
  # collapse to ⟨opaque⟩. Never surface raw hash bytes on the UI.
  defp render_argv(tokens) when is_list(tokens) do
    tokens
    |> Enum.map(fn
      %{token: {:safe_literal, value}} -> value
      %{token: {:flag_key, key}} -> key
      %{token: {:named_value, %{key: key}}} -> "#{key}=⟨opaque⟩"
      %{token: {:opaque_value_hash, _}} -> "⟨opaque⟩"
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp render_argv(_), do: ""

  # Infer the kind of run from the safe-literal subcommand in argv, so the
  # dashboard's Builds vs Tests split works without asking the client.
  # `once build …` and `cargo build …` alike land as "build"; `test` alike
  # as "test"; anything else as "generic".
  defp infer_kind(%RunStarted{argv_normalized: tokens}) when is_list(tokens) do
    literals =
      tokens
      |> Enum.flat_map(fn
        %{token: {:safe_literal, value}} -> [String.downcase(value)]
        _ -> []
      end)
      |> MapSet.new()

    cond do
      MapSet.member?(literals, "test") -> "test"
      MapSet.member?(literals, "build") -> "build"
      true -> "generic"
    end
  end

  defp infer_kind(_), do: "generic"

  # ContentRef carries a hash and optional size. Missing fields
  # collapse to safe defaults so the projector never blows up on a
  # partial event.
  defp content_ref_hash(%{hash: hash}) when is_binary(hash), do: nil_if_empty(hash)
  defp content_ref_hash(%{digest: digest}) when is_binary(digest), do: nil_if_empty(digest)
  defp content_ref_hash(_), do: nil

  defp content_ref_size(%{size_bytes: size}) when is_integer(size), do: size
  defp content_ref_size(%{size: size}) when is_integer(size), do: size
  defp content_ref_size(_), do: 0
end
