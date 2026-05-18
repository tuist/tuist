defmodule Cache.AnalyticsCircuitBreaker do
  @moduledoc """
  Wraps the shared analytics webhook breaker configuration.
  """

  require Logger

  @fuse_mode :sync
  @default_name __MODULE__

  def default_name, do: @default_name

  def accept_event?(key) when is_binary(key) do
    accept_event?(key, default_name())
  end

  def accept_event?(key, breaker_name) when is_binary(key) do
    name = ensure_installed(key, breaker_name)

    case :fuse.ask(name, @fuse_mode) do
      :ok -> true
      :blown -> false
      {:error, :not_found} -> true
    end
  end

  def allow_request?(key) when is_binary(key) do
    allow_request?(key, default_name())
  end

  def allow_request?(key, breaker_name) when is_binary(key) do
    accept_event?(key, breaker_name)
  end

  def record_success(key) when is_binary(key) do
    record_success(key, default_name())
  end

  def record_success(key, breaker_name) when is_binary(key) do
    name = ensure_installed(key, breaker_name)
    :fuse.reset(name)
    :ok
  end

  def record_failure(key, label, reason) when is_binary(key) and is_binary(label) do
    record_failure(key, label, reason, default_name())
  end

  def record_failure(key, label, reason, breaker_name) when is_binary(key) and is_binary(label) do
    name = ensure_installed(key, breaker_name)
    previous_state = :fuse.ask(name, @fuse_mode)

    :ok = :fuse.melt(name)

    if previous_state != :blown and :fuse.ask(name, @fuse_mode) == :blown do
      Logger.warning(
        "Opening analytics circuit for #{label} after repeated failures; " <>
          "dropping events for #{Cache.Config.analytics_cooldown_ms()} ms. Last failure: #{reason}"
      )
    end

    :ok
  end

  def req_fuse_options(key) when is_binary(key) do
    req_fuse_options(key, default_name())
  end

  def req_fuse_options(key, breaker_name) when is_binary(key) do
    name = ensure_installed(key, breaker_name)

    [
      fuse_name: name,
      fuse_mode: @fuse_mode,
      fuse_opts: fuse_options(),
      fuse_melt_func: fn _ -> false end
    ]
  end

  def reset(key) when is_binary(key) do
    reset(key, default_name())
  end

  def reset(key, breaker_name) when is_binary(key) do
    :fuse.remove(fuse_name(breaker_name, key))
    :ok
  end

  def melt?(%Req.Response{status: status}) when status >= 500, do: true
  def melt?(%Req.Response{}), do: false
  def melt?({:error, _reason}), do: true
  def melt?(_other), do: false

  defp ensure_installed(key, breaker_name) do
    name = fuse_name(breaker_name, key)

    case :fuse.ask(name, @fuse_mode) do
      {:error, :not_found} ->
        :global.trans({__MODULE__, name}, fn ->
          case :fuse.ask(name, @fuse_mode) do
            {:error, :not_found} ->
              :ok = :fuse.install(name, fuse_options())

            _ ->
              :ok
          end
        end)

      _ ->
        :ok
    end

    name
  end

  defp fuse_name(breaker_name, key) do
    {__MODULE__, breaker_name, key}
  end

  defp fuse_options do
    threshold = max(Cache.Config.analytics_failure_threshold(), 1)
    cooldown_ms = max(Cache.Config.analytics_cooldown_ms(), 1)
    tolerated_failures = max(threshold - 1, 0)

    {{:standard, tolerated_failures, cooldown_ms}, {:reset, cooldown_ms}}
  end
end
