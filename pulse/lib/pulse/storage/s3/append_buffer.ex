defmodule Pulse.Storage.S3.AppendBuffer do
  @moduledoc """
  Optional node-local coalescing for appends without an idempotency key.

  Reservations bound queued and executing input by caller count, estimated term
  bytes, and rows before a request enters the mailbox. Overflow uses the original
  unbuffered path; this is not ingest rate admission. Acknowledgments wait for the
  combined segment PUT and manifest CAS. Keyed requests never enter this process.

  Flushes are pipelined: each one encodes, uploads and registers its segment in
  its own linked process, so up to 16 segment uploads per tenant and signal
  overlap while the manifest owner folds their registrations into shared CAS
  commits. A batch flushes when its window expires or once it reaches a quarter
  of the reservation bounds, whichever comes first. While the owner is
  publishing, the window stretches to meet its next CAS (see `flush_delay/1`).

  A reserved caller hands its admission slot to the node's pending budget
  (`Pulse.IngestAdmission.handoff/1`) while it waits; see that module.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.Registry
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.AppendRegistry
  alias Pulse.Storage.S3.AppendSupervisor
  alias Pulse.Storage.S3.ManifestOwner

  @max_callers 2048
  @max_rows 400_000
  @max_bytes 32 * 1024 * 1024
  # One flush carries at most a quarter of the reservation, so a full buffer
  # always has several uploads in flight rather than one large serialized one.
  @flush_rows div(@max_rows, 4)
  @flush_bytes div(@max_bytes, 4)
  @flush_callers div(@max_callers, 4)
  @max_flushes 16
  # Upper bound on a window stretched to meet the manifest owner's next CAS.
  @max_adaptive_ms 2_000
  @idle_ms 30_000

  @doc "Read node-local buffer reservations without messaging owners or doing storage I/O."
  def stats do
    if Pulse.Runtime.whereis(AppendRegistry) do
      AppendRegistry
      |> Registry.select([{{:_, :_, :"$1"}, [], [:"$1"]}])
      |> Enum.reduce({0, 0, 0, 0}, fn table, totals -> add_stats(table, totals) end)
    else
      {0, 0, 0, 0}
    end
  rescue
    ArgumentError -> {0, 0, 0, 0}
  end

  defp add_stats(table, {buffers, callers, bytes, rows} = totals) do
    case :ets.lookup(table, :pending) do
      [{:pending, reserved_callers, reserved_bytes, reserved_rows}] ->
        {buffers + 1, callers + reserved_callers, bytes + reserved_bytes, rows + reserved_rows}

      _ ->
        totals
    end
  rescue
    # An idle or failed buffer can disappear during the scrape.
    ArgumentError -> totals
  end

  def append(signal, tenant, records, config, opts \\ []) do
    rows = length(records)
    bytes = :erlang.external_size(records)

    # `{:unbuffered, records}` hands the records back for the direct path, so
    # callers need not keep their own reference while a buffered append waits.
    if rows > @max_rows or bytes > @max_bytes do
      {:unbuffered, records}
    else
      # Copy before reservation: a heap/watchdog kill during detachment must
      # not strand credits for a message the owner never received.
      records = Pulse.JSON.detach(records)

      with {:ok, pid, admission} <- ensure_started(signal, tenant, config),
           :ok <- reserve(admission, bytes, rows) do
        call(
          pid,
          {:append, records, bytes, rows, opts},
          bytes,
          15_000 + 2 * Map.fetch!(config, :ingest_flush_interval_ms)
        )
      else
        :unbuffered -> {:unbuffered, records}
        other -> other
      end
    end
  end

  defp reserve(table, bytes, rows) do
    case :ets.update_counter(table, :pending, [{2, 1}, {3, bytes}, {4, rows}]) do
      [callers, total_bytes, total_rows]
      when callers <= @max_callers and total_bytes <= @max_bytes and total_rows <= @max_rows ->
        :ok

      _ ->
        release(table, bytes, rows)
        :unbuffered
    end
  rescue
    ArgumentError -> :unbuffered
  end

  defp release(table, bytes, rows), do: :ets.update_counter(table, :pending, [{2, -1}, {3, -bytes}, {4, -rows}])

  # `GenServer.call/3`, split so the caller can drop its copy of the records
  # once the buffer has it: send, collect garbage, hand the admission slot to
  # the pending budget, then wait. The reply alias discards late replies.
  defp call(pid, request, bytes, timeout) do
    mref = Process.monitor(pid, alias: :demonitor)
    send(pid, {:"$gen_call", {self(), [:alias | mref]}, request})
    # Charge what the waiting caller still retains (its compacted heap and
    # referenced binaries) plus the buffer's copy, about twice its external size.
    Pulse.IngestAdmission.handoff(retained_bytes() + 2 * bytes)

    receive do
      {[:alias | ^mref], reply} ->
        Process.demonitor(mref, [:flush])
        reply

      {:DOWN, ^mref, _, _, reason} when reason in [:noproc, :normal] ->
        {:error, :owner_overloaded}

      {:DOWN, ^mref, _, _, reason} ->
        exit({reason, {GenServer, :call, [pid, :append, timeout]}})
    after
      # A timed-out caller does NOT release its reservation: its message or
      # native publication can still be in progress. Only the owner releases it.
      timeout ->
        Process.demonitor(mref, [:flush])
        {:error, :timeout}
    end
  end

  defp retained_bytes do
    :erlang.garbage_collect()
    [memory: memory, binary: binaries] = Process.info(self(), [:memory, :binary])
    Enum.reduce(binaries, memory, fn {_id, size, _refc}, total -> total + size end)
  end

  defp ensure_started(signal, tenant, config) do
    identity = :crypto.hash(:sha256, :erlang.term_to_binary(config, [:deterministic]))
    key = {identity, tenant, signal}

    case Registry.lookup(AppendRegistry, key) do
      [{pid, admission}] when is_reference(admission) ->
        {:ok, pid, admission}

      [{_pid, _starting}] ->
        :unbuffered

      [] ->
        opts = [key: key, signal: signal, tenant: tenant, config: config]
        spec = %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :transient}

        case DynamicSupervisor.start_child(Pulse.Runtime.name(AppendSupervisor), Pulse.Runtime.child_spec(spec)) do
          {:ok, _pid} -> lookup(key)
          {:error, {:already_started, _pid}} -> lookup(key)
          {:error, _} -> {:error, :owner_overloaded}
        end
    end
  end

  defp lookup(key) do
    case Registry.lookup(AppendRegistry, key) do
      [{pid, admission}] when is_reference(admission) -> {:ok, pid, admission}
      _ -> :unbuffered
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {AppendRegistry, opts[:key]}})

  @impl true
  def init(opts) do
    Process.set_label({:pulse, :append_buffer})
    admission = :ets.new(__MODULE__, [:set, :public, write_concurrency: true])
    true = :ets.insert(admission, {:pending, 0, 0, 0})
    Registry.update_value(AppendRegistry, opts[:key], fn _ -> admission end)

    state = %{
      signal: opts[:signal],
      tenant: opts[:tenant],
      config: opts[:config],
      admission: admission,
      pending: [],
      pending_bytes: 0,
      pending_rows: 0,
      flushing: 0,
      # Flushes still encoding or uploading, the moving average of how long a
      # flush takes to reach the manifest owner (ms), and when one last did.
      uploading: 0,
      upload_ms: nil,
      upload_deviation_ms: 0,
      registered_at: nil,
      timer: nil
    }

    {:ok, state, @idle_ms}
  end

  @impl true
  def handle_call({:append, records, bytes, rows, opts}, from, state) do
    state = %{
      state
      | pending: [{from, records, bytes, rows, opts, System.monotonic_time()} | state.pending],
        pending_bytes: state.pending_bytes + bytes,
        pending_rows: state.pending_rows + rows
    }

    state =
      cond do
        state.pending_bytes >= @flush_bytes or state.pending_rows >= @flush_rows or
            length(state.pending) >= @flush_callers ->
          flush(state)

        state.timer ->
          state

        true ->
          schedule(state)
      end

    {:noreply, state, @idle_ms}
  end

  defp schedule(state) do
    token = make_ref()
    ref = Process.send_after(self(), {:flush, token}, flush_delay(state))
    %{state | timer: {ref, token}}
  end

  # The manifest owner publishes one CAS at a time, and every flush must wait
  # for the publication in flight before its own. A segment that reaches the
  # owner before that publication ends joins the next one, and one that
  # arrives later waits a whole publication more. So while the owner is
  # publishing, keep collecting until just early enough to make the next CAS:
  # the window adapts to the owner's commit time, more requests share one
  # segment, and acknowledgments come about as early as with a short window. An
  # idle owner, or no estimate yet, keeps the configured window.
  defp flush_delay(state) do
    base = Map.fetch!(state.config, :ingest_flush_interval_ms)

    with upload when is_integer(upload) <- state.upload_ms,
         %{} = commit <- ManifestOwner.commit_eta(state.tenant, Atom.to_string(state.signal)) do
      now = System.monotonic_time(:millisecond)
      # Encode and PUT must finish before the owner's next flush. Requests
      # arriving within the lead wait a whole publication more, so keep it
      # tight: two mean deviations cover upload jitter, as in TCP RTO.
      lead = upload + 2 * state.upload_deviation_ms + commit.flush_interval_ms
      deadline = commit.eta + commit.flush_interval_ms - lead

      # Too late for the next publication? If something else will start it
      # anyway, aim for the one after; otherwise this flush starts it.
      deadline =
        if deadline - now < base and next_commit_follows?(state, commit),
          do: deadline + commit.estimate + commit.flush_interval_ms,
          else: deadline

      deadline |> Kernel.-(now) |> max(base) |> min(max(base, @max_adaptive_ms))
    else
      _ -> base
    end
  end

  # Segments queued at the owner, still uploading, or registered after the
  # publication in flight began all start another one when it ends.
  defp next_commit_follows?(state, commit),
    do:
      commit.queued > 0 or state.uploading > 0 or
        (is_integer(state.registered_at) and state.registered_at >= commit.since)

  @impl true
  def handle_info({:flush, token}, %{timer: {_ref, token}} = state),
    do: {:noreply, flush(%{state | timer: nil}), @idle_ms}

  def handle_info({:flush, _obsolete}, state), do: {:noreply, state, @idle_ms}

  def handle_info({:uploaded, started}, state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - started

    {average, deviation} =
      case state.upload_ms do
        nil -> {elapsed, div(elapsed, 2)}
        average -> {div(average * 7 + elapsed, 8), div(state.upload_deviation_ms * 3 + abs(elapsed - average), 4)}
      end

    state = %{state | uploading: state.uploading - 1, registered_at: now}
    {:noreply, %{state | upload_ms: average, upload_deviation_ms: deviation}, @idle_ms}
  end

  def handle_info({:flushed, uploaded?}, state) do
    # A flush that failed before its upload finished is no longer uploading.
    state = %{state | flushing: state.flushing - 1, uploading: state.uploading - if(uploaded?, do: 0, else: 1)}
    # A batch that became due while every upload slot was busy goes now.
    state = if state.pending != [] and state.timer == nil, do: flush(state), else: state
    {:noreply, state, @idle_ms}
  end

  def handle_info(:timeout, %{pending: [], flushing: 0} = state), do: {:stop, :normal, state}
  def handle_info(:timeout, state), do: {:noreply, state, @idle_ms}

  # At the upload limit the batch keeps growing (within the reservation) and
  # goes when an upload finishes. The obsolete timer, if any, is ignored.
  defp flush(%{pending: []} = state), do: state
  defp flush(%{flushing: flushing} = state) when flushing >= @max_flushes, do: %{state | timer: nil}

  defp flush(state) do
    if state.timer, do: Process.cancel_timer(elem(state.timer, 0))
    pending = Enum.reverse(state.pending)
    buffer = self()

    # Linked: a crashed upload takes the buffer and its callers down, exactly
    # as an inline flush would, instead of leaving callers without a reply.
    {:ok, _pid} =
      Pulse.Runtime.Task.start_link(fn ->
        Process.set_label({:pulse, :ingest_flush})
        publish(pending, state, buffer)
        send(buffer, {:flushed, Process.get(:uploaded, false)})
      end)

    %{
      state
      | pending: [],
        pending_bytes: 0,
        pending_rows: 0,
        flushing: state.flushing + 1,
        uploading: state.uploading + 1,
        timer: nil
    }
  end

  defp publish(pending, state, buffer) do
    started = System.monotonic_time(:millisecond)

    records =
      Enum.flat_map(pending, fn {_from, records, _bytes, _rows, _opts, enqueued} ->
        Pulse.Metrics.stage(state.signal, :buffer_wait, enqueued)
        records
      end)

    uploaded = fn ->
      Process.put(:uploaded, true)
      send(buffer, {:uploaded, started})
    end

    opts = [split_admission_errors: true, on_uploaded: uploaded]
    result = S3.append_unbuffered(state.signal, state.tenant, records, opts, state.config)

    # An invalid input must not poison other valid requests sharing a flush.
    # Encoding errors occur before any upload. Never fall back after a storage
    # error: a lost response could have published the combined segment already.
    if encoding_error?(result) do
      pending
      |> Pulse.Runtime.Task.async_stream(&split_reply(&1, state),
        max_concurrency: 8,
        ordered: false,
        timeout: :infinity
      )
      |> Stream.run()
    else
      # After PUT/CAS begins, a moving floor can reject the combined segment.
      # Fresh siblings must retry, not receive a permanent drop; do not split an
      # ambiguous publication into new segments that could duplicate its data.
      result =
        case {result, pending} do
          {{:error, :retention_expired}, [_, _ | _]} -> {:error, :retention_floor_advanced}
          _ -> result
        end

      Enum.each(pending, &reply_pending(&1, result, state))
    end
  end

  defp split_reply({_from, records, _bytes, _rows, opts, _enqueued} = pending, state) do
    result =
      try do
        S3.append_unbuffered(state.signal, state.tenant, records, opts, state.config)
      rescue
        _error -> {:error, :storage_unavailable}
      catch
        :exit, _reason -> {:error, :storage_unavailable}
      end

    reply_pending(pending, result, state)
  end

  defp reply_pending({from, _records, bytes, rows, _opts, _enqueued}, result, state) do
    # Native work keeps its reservation until it finishes, even if its caller
    # timed out. Replies are sent from the bounded tasks as each write completes.
    release(state.admission, bytes, rows)
    GenServer.reply(from, result)
  end

  # Retention preflight failures precede PUT, so split valid siblings safely.
  # Once PUT/CAS starts, storage errors remain ambiguous and never split.
  defp encoding_error?({:error, :payload_too_large}), do: true

  defp encoding_error?({:error, {:admission_rejected, reason}}) when reason in [:retention_expired, :timestamp_too_new],
    do: true

  defp encoding_error?({:error, {kind, _}}) when kind in [:encode_failed, :attribute_key_collision], do: true
  defp encoding_error?(_), do: false
end
