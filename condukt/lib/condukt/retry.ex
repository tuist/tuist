defmodule Condukt.Retry do
  @moduledoc """
  Retry policy applied to provider calls in the native runtime.

  Each call to the LLM is wrapped with bounded exponential backoff plus
  jitter. By default, the following are retried:

  - HTTP `408`, `425`, `429`, `500`, `502`, `503`, `504`
  - Streaming failures whose underlying `cause` matches the list above
  - Stream errors whose textual reason mentions overload, rate-limit,
    or timeout when no structured cause is available

  Streaming calls only retry while no event has been emitted to the
  caller. Once a `:text` or `:thinking` chunk has been delivered the
  policy stops, so the consumer never sees the same content twice. The
  underlying error is surfaced and the caller can decide how to recover
  (re-enqueue, fail open, etc.).

  ## Configuration

  Pass `:retry` to any session entry point:

      Condukt.run("Hello", retry: false)
      Condukt.run("Hello", retry: [max_attempts: 5, base_delay_ms: 500])
      Condukt.run("Hello", retry: %Condukt.Retry{max_attempts: 2})

  Set globally via `Application.put_env(:condukt, :retry, ...)` or
  per-agent via `start_link(retry: ...)`.

  ## Custom classifier

  Provide a `:classify` callback to override the default error
  classification:

      classify = fn
        %MyApp.RateLimit{} -> :retry
        _ -> :stop
      end

      Condukt.run("Hello", retry: [classify: classify])
  """

  defstruct max_attempts: 3,
            base_delay_ms: 300,
            max_delay_ms: 5_000,
            classify: &__MODULE__.default_classify/1

  @retryable_statuses [408, 425, 429, 500, 502, 503, 504]

  @doc """
  Returns the default retry policy.
  """
  def default, do: %__MODULE__{}

  @doc """
  Returns a policy that performs a single attempt with no retries.
  """
  def disabled, do: %__MODULE__{max_attempts: 1}

  @doc """
  Normalizes a session-level `:retry` option into a policy struct.

  Accepts:

  - `nil` / `true` → `default/0`
  - `false` → `disabled/0`
  - A `%Condukt.Retry{}` struct → returned as-is
  - A keyword list of overrides merged into `default/0`
  """
  def normalize(nil), do: default()
  def normalize(true), do: default()
  def normalize(false), do: disabled()
  def normalize(%__MODULE__{} = policy), do: policy

  def normalize(opts) when is_list(opts) do
    struct!(default(), opts)
  end

  @doc """
  Runs `fun.()` and retries transient failures.

  `emitted?.()` must return `true` if the call has already produced a
  side-effect visible to the caller (e.g. a stream chunk). The policy
  stops retrying as soon as `emitted?` reports `true`, so the caller
  sees partial output followed by the underlying error rather than a
  silent re-attempt.

  `fun` returns `{:ok, value}` / `{:error, reason}` (or any non-tuple
  value). Non-error results are returned verbatim.

  The optional `wait` callback receives the backoff in milliseconds. It
  returns `:ok` to retry or `{:error, reason}` to stop. By default it sleeps;
  native sessions use an interruptible receive so cancellation wakes it.
  """
  def with_retry(%__MODULE__{} = policy, emitted?, fun, wait \\ &Process.sleep/1)
      when is_function(emitted?, 0) and is_function(fun, 0) and is_function(wait, 1) do
    do_with_retry(policy, emitted?, fun, wait, 1)
  end

  defp do_with_retry(%__MODULE__{max_attempts: max} = policy, emitted?, fun, wait, attempt) do
    case fun.() do
      {:error, reason} = error when attempt < max ->
        with true <- not emitted?.() and retryable?(policy, reason),
             :ok <- wait.(backoff(policy, attempt)) do
          do_with_retry(policy, emitted?, fun, wait, attempt + 1)
        else
          false -> error
          {:error, _} = interrupted -> interrupted
        end

      result ->
        result
    end
  end

  defp retryable?(%__MODULE__{classify: classify}, reason) when is_function(classify, 1) do
    classify.(reason) == :retry
  end

  @doc false
  def default_classify(%ReqLLM.Error.API.Stream{cause: cause}) when not is_nil(cause) do
    default_classify(cause)
  end

  def default_classify(%ReqLLM.Error.API.Stream{reason: reason}) when is_binary(reason) do
    if transient_reason?(reason), do: :retry, else: :stop
  end

  def default_classify(%ReqLLM.Error.API.Request{status: status}) when status in @retryable_statuses, do: :retry

  def default_classify(%ReqLLM.Error.API.Response{status: status}) when status in @retryable_statuses, do: :retry

  def default_classify(_), do: :stop

  defp transient_reason?(reason) do
    needles = ["overloaded", "rate limit", "timeout", "timed out", " 503", " 504", " 429"]
    downcased = String.downcase(reason)
    Enum.any?(needles, &String.contains?(downcased, &1))
  end

  defp backoff(%__MODULE__{base_delay_ms: base, max_delay_ms: maxd}, attempt) do
    delay = min(base * Integer.pow(2, attempt - 1), maxd)
    jitter = :rand.uniform(div(delay, 2) + 1) - 1
    delay + jitter
  end
end
