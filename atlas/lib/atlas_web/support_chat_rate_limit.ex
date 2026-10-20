defmodule AtlasWeb.SupportChatRateLimit do
  @moduledoc false

  alias Atlas.RateLimit

  # The source limit is intentionally looser than the email subscription
  # limit: a support conversation can involve a few quick clarifying messages.
  # The email limit remains useful while the ingress load balancer reports a
  # shared source address for every visitor.
  @per_ip_minute {:timer.minutes(1), 60}
  @per_ip_hour {:timer.hours(1), 600}
  @per_address {:timer.minutes(15), 20}

  def check(ip_address, email) do
    with :ok <- hit("support_chat:ip:minute:#{ip_address}", @per_ip_minute),
         :ok <- hit("support_chat:ip:hour:#{ip_address}", @per_ip_hour) do
      hit("support_chat:address:#{address_key(email)}", @per_address)
    end
  end

  defp hit(key, {scale, limit}) do
    case RateLimit.hit(key, scale, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, ceil(retry_after_ms / 1000)}
    end
  end

  defp address_key(email) when is_binary(email) do
    :sha256
    |> :crypto.hash(String.downcase(String.trim(email)))
    |> Base.encode16(case: :lower)
  end

  defp address_key(_email), do: "missing"
end
