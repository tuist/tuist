defmodule AtlasWeb.SubscriptionRateLimit do
  @moduledoc """
  Rate limits the public newsletter subscription endpoint.

  The endpoint is unauthenticated and sends an email on every accepted
  request, so without a limit it doubles as an open relay for confirmation
  mail to arbitrary addresses.

  Two limits, because they stop different attacks. The per-address limit is
  the one that protects a person: somebody bombing a single inbox from many
  sources stays under any per-source limit, but every one of those requests
  targets the same address. The per-address window is deliberately much wider
  than the per-source one, since a real person submits the form once and then
  waits for the email.

  The per-address limit is also the only one that bites today, because the
  ingress load balancer hides the caller's address. See `AtlasWeb.ClientIP`.
  """

  alias Atlas.RateLimit

  # The per-source limits are deliberately loose. The ingress load balancer
  # does not preserve the caller's address, so today every request shares one
  # source and these act as a ceiling on total volume rather than a per-caller
  # limit. Tighten them once the balancer speaks the PROXY protocol and the
  # real address survives; a five-a-minute limit right now would lock the form
  # for everybody at once.
  @per_ip_minute {:timer.minutes(1), 30}
  @per_ip_hour {:timer.hours(1), 300}
  @per_address {:timer.minutes(15), 1}

  @doc """
  Returns `:ok`, or `{:error, retry_after_seconds}` when a limit is hit.
  """
  def check(ip_address, email) do
    with :ok <- hit("subscriptions:ip:minute:#{ip_address}", @per_ip_minute),
         :ok <- hit("subscriptions:ip:hour:#{ip_address}", @per_ip_hour) do
      hit("subscriptions:address:#{address_key(email)}", @per_address)
    end
  end

  defp hit(key, {scale, limit}) do
    case RateLimit.hit(key, scale, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after_ms} -> {:error, ceil(retry_after_ms / 1000)}
    end
  end

  # The address is only ever used as a counter key, so it is hashed rather
  # than kept in an in-memory table in the clear.
  defp address_key(email) when is_binary(email) do
    :sha256 |> :crypto.hash(String.downcase(String.trim(email))) |> Base.encode16(case: :lower)
  end

  defp address_key(_email), do: "missing"
end
