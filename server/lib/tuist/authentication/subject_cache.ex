defmodule Tuist.Authentication.SubjectCache do
  @moduledoc """
  Disposable node-local authentication snapshots with at most one minute of
  staleness. Hits never renew the deadline or extend verified credential expiry.
  Membership/display invalidation must not clear this cache.
  """
  import Cachex.Spec, only: [expiration: 1, hook: 1]

  alias Tuist.Authentication
  alias Tuist.Authentication.SingleFlight
  alias Tuist.Environment

  @cache :auth_subjects
  @ttl to_timeout(minute: 1)

  def child_spec(opts) do
    cache = Keyword.get(opts, :cache, @cache)

    SingleFlight.cache_child_spec(__MODULE__, cache,
      expiration: expiration(default: @ttl),
      hooks: [hook(module: Cachex.Limit.Scheduled, args: {10_000, [], []})]
    )
  end

  def fetch(token, opts \\ []) do
    context = %{
      cache: Keyword.get(opts, :cache, @cache),
      key: :crypto.mac(:hmac, :sha256, Environment.secret_key_password(), token),
      monotonic: Keyword.get(opts, :monotonic, fn -> System.monotonic_time(:millisecond) end),
      wall: Keyword.get(opts, :wall, fn -> System.system_time(:millisecond) end),
      ttl: min(Keyword.get(opts, :ttl, @ttl), @ttl)
    }

    context.cache
    |> SingleFlight.fetch(context.key, fn -> load(token, context) end)
    |> result(token, opts, context)
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp load(token, context) do
    started_at = context.monotonic.()

    case Authentication.authenticated_subject_snapshot(token) do
      nil -> {:ignore, nil}
      snapshot -> commit(snapshot, started_at, context)
    end
  end

  defp commit(snapshot, started_at, context) do
    remaining =
      case snapshot.expires_at do
        nil -> context.ttl
        expiry -> min(context.ttl, max(expiry * 1_000 - context.wall.(), 0))
      end

    deadline = min(started_at + context.ttl, context.monotonic.() + remaining)
    snapshot = Map.put(snapshot, :valid_until, deadline)

    cond do
      context.monotonic.() >= started_at + context.ttl -> {:ignore, {:error, :unavailable}}
      valid?(snapshot, context) -> {:commit, snapshot, expire: max(deadline - context.monotonic.(), 1)}
      true -> {:ignore, nil}
    end
  end

  defp result({:commit, snapshot}, token, opts, context), do: result(snapshot, token, opts, context)
  defp result({:ignore, nil}, _token, _opts, _context), do: {:ok, nil}
  defp result(nil, _token, _opts, _context), do: {:ok, nil}

  defp result(%{valid_until: _} = snapshot, token, opts, context) do
    if valid?(snapshot, context) do
      {:ok, snapshot}
    else
      refresh(token, opts, context)
    end
  end

  defp result(_error, _token, _opts, _context), do: {:error, :unavailable}

  defp refresh(token, opts, context) do
    if Keyword.get(opts, :refreshed, false) do
      {:error, :unavailable}
    else
      Cachex.del(context.cache, context.key)
      fetch(token, Keyword.put(opts, :refreshed, true))
    end
  end

  defp valid?(snapshot, context) do
    context.monotonic.() < snapshot.valid_until and
      (is_nil(snapshot.expires_at) or context.wall.() < snapshot.expires_at * 1_000)
  end
end
