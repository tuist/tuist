defmodule TuistWeb.RateLimit.AgentAuth do
  @moduledoc false

  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentTokenBucket

  @ip_limit 60
  @subject_limit 20
  @window_seconds 60 * 60
  @registration_limits %{
    anonymous: %{ip: 5, service: 100},
    identity_assertion: %{ip: 60, service: 1000},
    service_auth: %{ip: 60, service: 1000}
  }

  def hit_registration(conn, registration_type) when is_map_key(@registration_limits, registration_type) do
    limits = Map.fetch!(@registration_limits, registration_type)

    with {:allow, _count} <- maybe_hit(registration_ip_key(conn, registration_type), limits.ip),
         {:allow, _count} <- maybe_hit("agent_auth:service:#{registration_type}", limits.service) do
      {:allow, 1}
    else
      {:deny, _limit} = deny -> deny
    end
  rescue
    _ -> {:allow, 1}
  end

  def hit(conn, subject \\ nil) do
    with {:allow, _count} <- maybe_hit("agent_auth:ip:#{TuistWeb.RemoteIp.get(conn)}", @ip_limit),
         {:allow, _count} <- maybe_hit(subject_key(subject), @subject_limit) do
      {:allow, 1}
    else
      {:deny, _limit} = deny -> deny
    end
  rescue
    _ -> {:allow, 1}
  end

  defp maybe_hit(nil, _limit), do: {:allow, 1}

  defp maybe_hit(key, limit) do
    if is_nil(Tuist.Environment.redis_url()) do
      InMemory.hit(key, to_timeout(hour: 1), limit)
    else
      fill_rate = limit / @window_seconds

      PersistentTokenBucket.hit_with_fallback(
        key,
        fill_rate,
        limit,
        1,
        fn -> InMemory.hit(key, to_timeout(hour: 1), limit) end
      )
    end
  end

  defp registration_ip_key(conn, registration_type) do
    case TuistWeb.RemoteIp.get(conn) do
      ip when is_binary(ip) and ip != "" -> "agent_auth:registration:#{registration_type}:ip:#{ip}"
      _ -> nil
    end
  end

  defp subject_key(nil), do: nil

  defp subject_key(subject) when is_binary(subject) do
    digest =
      subject
      |> String.downcase()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "agent_auth:subject:#{digest}"
  end
end
