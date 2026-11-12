defmodule Condukt.Session.Compaction do
  @moduledoc false

  # The session owns this state. Workers only summarize a captured prefix;
  # neither they nor a running inference task may replace session history.
  alias Condukt.Compactor
  alias Condukt.Message
  alias Condukt.Session.Translate
  alias Condukt.Telemetry
  alias Condukt.TraceContext

  require Logger

  defstruct [:spec, :policy, :supervisor, :task, :timer, :prefix, :result, :waiter, :attempted, :usage, :trace_context]

  def apply(nil, messages, _metadata), do: messages

  def apply(compactor, messages, metadata) do
    case compact(compactor, messages, metadata) do
      {:ok, compacted} -> compacted
      {:error, _reason} -> messages
    end
  end

  def new(spec, background, _model) when background in [nil, false] do
    {:ok, %__MODULE__{spec: spec}}
  end

  def new(spec, true, model), do: new(spec, [], model)

  def new(spec, opts, model) when is_list(opts) and not is_nil(spec) do
    if Keyword.keyword?(opts) do
      new_policy(spec, opts, model)
    else
      {:error, {:invalid_background_compaction, opts}}
    end
  end

  def new(_spec, opts, _model), do: {:error, {:invalid_background_compaction, opts}}

  defp new_policy(spec, opts, model) do
    policy = %{
      window: Keyword.get_lazy(opts, :context_window, fn -> context_window(model) end),
      background: Keyword.get(opts, :background_threshold, 0.65),
      blocking: Keyword.get(opts, :blocking_threshold, 0.9),
      keep: Keyword.get(opts, :keep_recent_tokens, 20_000),
      timeout: Keyword.get(opts, :timeout, 60_000)
    }

    keys = [:context_window, :background_threshold, :blocking_threshold, :keep_recent_tokens, :timeout]

    if Keyword.keys(opts) -- keys == [] and valid_policy?(policy) do
      {:ok, %__MODULE__{spec: spec, policy: policy}}
    else
      {:error, {:invalid_background_compaction, opts}}
    end
  end

  defp valid_policy?(%{window: window, background: background, blocking: blocking, keep: keep, timeout: timeout}) do
    positive_integer?(window) and is_number(background) and is_number(blocking) and background > 0 and
      background < blocking and blocking < 1 and is_integer(keep) and keep >= 0 and positive_integer?(timeout)
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  def enabled?(%__MODULE__{policy: policy}), do: not is_nil(policy)

  # A blocked inference caller is kept as a GenServer `from`, not awaited in
  # the session process. Abort, clear, history and subscriptions stay usable.
  def checkpoint(compaction, messages, overhead, from, metadata, phase \\ :background, protected_count \\ 1) do
    {compaction, messages, error} = take_result(compaction, messages)

    cond do
      phase in [:fallback, :manual] and not is_nil(error) ->
        {:error, error, compaction, messages}

      phase == :manual ->
        {:continue, compaction, messages}

      due?(compaction, messages, overhead, :blocking) ->
        block(compaction, messages, overhead, from, metadata, phase, protected_count)

      true ->
        {:continue, background(compaction, messages, overhead, metadata, protected_count), messages}
    end
  end

  def background(compaction, messages, overhead, metadata, protected_count \\ 1) do
    prefix = prefix(messages, compaction.policy.keep, protected_count)

    if is_nil(compaction.task) and is_nil(compaction.result) and prefix != [] and
         prefix != compaction.attempted and due?(compaction, messages, overhead, :background) do
      start(compaction, prefix, metadata)
    else
      compaction
    end
  end

  defp block(compaction, messages, _overhead, _from, _metadata, :fallback, _protected_count) do
    {:error, :context_limit, compaction, messages}
  end

  defp block(%__MODULE__{task: %Task{}} = compaction, messages, overhead, from, metadata, _phase, _protected_count) do
    {:wait, %{compaction | waiter: {from, overhead, metadata, :background}}, messages}
  end

  defp block(compaction, messages, overhead, from, metadata, _phase, protected_count) do
    # Fresh foreground work can cover more than a speculative prefix, but
    # never touches the active prompt and suffix or splits an assistant/tool batch.
    case prefix(messages, 0, protected_count) do
      [] ->
        {:error, :context_limit, compaction, messages}

      prefix ->
        compaction = start(compaction, prefix, metadata)
        {:wait, %{compaction | waiter: {from, overhead, metadata, :fallback}}, messages}
    end
  end

  def usage(compaction, %{usage: %{input_tokens: tokens} = usage}, messages) when is_integer(tokens) do
    usage = if Map.has_key?(usage, :input_includes_cached), do: usage, else: ReqLLM.Usage.normalize(usage)

    tokens =
      if usage.input_includes_cached do
        tokens
      else
        tokens + (usage[:cached_tokens] || 0) + (usage[:cache_creation_tokens] || 0)
      end

    %{compaction | usage: {tokens, messages}}
  end

  def usage(compaction, _response, _messages), do: %{compaction | usage: nil}

  def tokens(%__MODULE__{usage: {tokens, prefix}}, messages, overhead) do
    if List.starts_with?(messages, prefix) do
      tokens + estimate(Enum.drop(messages, length(prefix))) + overhead.output
    else
      estimate(messages) + overhead.input + overhead.output
    end
  end

  def tokens(_compaction, messages, overhead), do: estimate(messages) + overhead.input + overhead.output

  def due?(compaction, messages, overhead, threshold) do
    tokens(compaction, messages, overhead) >= compaction.policy.window * Map.fetch!(compaction.policy, threshold)
  end

  def estimate(messages), do: Enum.reduce(messages, 0, &(message_tokens(&1) + &2))

  def data_tokens(nil), do: 0
  def data_tokens(data) when is_binary(data), do: div(byte_size(data) + 3, 4)
  def data_tokens(data), do: data |> JSON.encode!() |> data_tokens()

  # A boundary may precede a user or an assistant, never a tool result. Walking
  # back through the whole batch keeps calls and all their results together.
  def prefix(messages, keep, protected_count \\ 1) do
    {cut, _tokens} =
      messages
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce_while({0, 0}, fn {message, index}, {_cut, tokens} ->
        tokens = tokens + message_tokens(message)

        if tokens >= keep and message.role != :tool_result do
          {:halt, {index, tokens}}
        else
          {:cont, {0, tokens}}
        end
      end)

    Enum.take(messages, min(cut, max(0, length(messages) - protected_count)))
  end

  def start(compaction, prefix, metadata) do
    compaction = cancel(compaction)
    {:ok, supervisor} = ensure_supervisor(compaction.supervisor)
    spec = compaction.spec
    trace_context = compaction.trace_context

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        TraceContext.attach(trace_context)
        compact(spec, prefix, metadata)
      end)

    timer = Process.send_after(self(), {:compaction_timeout, task.ref}, compaction.policy.timeout)
    %{compaction | supervisor: supervisor, task: task, timer: timer, prefix: prefix, attempted: prefix}
  end

  def complete(%__MODULE__{task: %Task{ref: ref}} = compaction, ref, result) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(compaction.timer)
    %{compaction | task: nil, timer: nil, result: result}
  end

  def complete(compaction, _ref, _result), do: compaction

  def take_result(%__MODULE__{result: {:ok, replacement}, prefix: prefix} = compaction, messages) do
    updated =
      if List.starts_with?(messages, prefix) do
        replacement ++ Enum.drop(messages, length(prefix))
      else
        messages
      end

    usage = if updated == messages, do: compaction.usage
    {%{compaction | prefix: nil, result: nil, usage: usage}, updated, nil}
  end

  def take_result(%__MODULE__{result: {:error, reason}} = compaction, messages) do
    {%{compaction | prefix: nil, result: nil}, messages, reason}
  end

  def take_result(compaction, messages), do: {compaction, messages, nil}

  def cancel(compaction) do
    if compaction.timer, do: Process.cancel_timer(compaction.timer)
    if compaction.task, do: Task.shutdown(compaction.task, :brutal_kill)
    %{compaction | task: nil, timer: nil, prefix: nil, result: nil}
  end

  def stop(%__MODULE__{supervisor: nil}), do: :ok

  def stop(%__MODULE__{supervisor: supervisor}) do
    if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
    :ok
  end

  def compact(spec, messages, metadata) do
    started = System.monotonic_time()
    before_bytes = :erlang.external_size(messages)
    Telemetry.emit([:compact, :start], %{system_time: System.system_time()}, metadata)
    result = Compactor.compact(spec, messages)

    {compacted, status} =
      case result do
        {:ok, compacted} ->
          {compacted, :ok}

        {:error, _reason} ->
          Logger.warning("compaction failed; preserving original history")
          {messages, :error}
      end

    Telemetry.emit(
      [:compact, :stop],
      %{
        duration: System.monotonic_time() - started,
        before: length(messages),
        after: length(compacted),
        before_bytes: before_bytes,
        after_bytes: :erlang.external_size(compacted)
      },
      Map.merge(metadata, %{status: status, changed: compacted != messages})
    )

    result
  end

  defp message_tokens(%Message{} = message) do
    8 + content_tokens(message) + data_tokens(message.images) + data_tokens(message.tool_call_id)
  end

  defp content_tokens(%Message{role: :tool_result, content: content}) do
    content |> Translate.encode_tool_result() |> data_tokens()
  end

  defp content_tokens(%Message{role: :assistant, content: blocks}) when is_list(blocks) do
    Enum.reduce(blocks, 0, fn
      {:tool_call, id, name, args}, tokens ->
        tokens + 8 + data_tokens(id) + data_tokens(name) + data_tokens(args)

      {_kind, text}, tokens ->
        tokens + data_tokens(text)
    end)
  end

  defp content_tokens(%Message{content: content}), do: data_tokens(content)

  defp context_window(model) do
    case ReqLLM.model(model) do
      {:ok, %{limits: limits}} when is_map(limits) -> limits[:input] || limits[:context]
      _ -> nil
    end
  end

  defp ensure_supervisor(nil), do: Task.Supervisor.start_link()
  defp ensure_supervisor(supervisor), do: {:ok, supervisor}
end
