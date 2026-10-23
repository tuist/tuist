defmodule Atlas.Licenses.RateLimiter do
  @moduledoc """
  Bounds online validation attempts per opaque client or license identifier.

  Counters live in PostgreSQL, so replica count and pod restarts do not change
  the effective limit. Identifiers are hashed by the shared limiter.
  """

  alias Atlas.RateLimit

  @default_max_attempts 60
  @default_window_milliseconds :timer.minutes(1)

  def check(identifier) when is_binary(identifier) do
    config = Application.get_env(:atlas, __MODULE__, [])
    limit = positive_integer(config[:max_attempts], @default_max_attempts)
    window = positive_integer(config[:window_milliseconds], @default_window_milliseconds)

    case RateLimit.hit("license_validation:#{identifier}", window, limit) do
      {:allow, _count} -> :ok
      {:deny, milliseconds} -> {:error, div(milliseconds + 999, 1000)}
    end
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
