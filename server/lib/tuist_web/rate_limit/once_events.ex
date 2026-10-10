defmodule TuistWeb.RateLimit.OnceEvents do
  @moduledoc """
  Rate limiting for the Once events gRPC endpoint.

  Bounds what one client address can spend on calls, valid credential or not, and
  refuses an over-limit call before any credential work happens. The ingress sets
  `x-forwarded-for` to the connecting address and is the only way to reach the
  port, so a call without it is not limited.
  """
  @behaviour GRPC.Server.Interceptor

  alias Tuist.Environment
  alias TuistWeb.RateLimit

  @max_address_bytes 64

  @impl true
  def init(opts), do: opts

  @impl true
  def call(request, stream, next, _opts) do
    case client_address(stream) do
      nil -> next.(request, stream)
      address -> hit(address, request, stream, next)
    end
  end

  defp hit(address, request, stream, next) do
    result =
      RateLimit.hit("once-events:#{address}",
        limit: Environment.once_events_rate_limit_bucket_size(),
        window: to_timeout(minute: 1),
        failure_policy: :local
      )

    case result do
      {:allow, _count} ->
        next.(request, stream)

      {:deny, _limit} ->
        {:error, GRPC.RPCError.exception(status: :resource_exhausted, message: "too many requests")}
    end
  end

  defp client_address(stream) do
    headers = GRPC.Stream.get_headers(stream) || %{}

    with forwarded when is_binary(forwarded) <- header(headers, "x-forwarded-for"),
         [first | _] <- String.split(forwarded, ","),
         address when address != "" <- String.trim(first) do
      binary_part(address, 0, min(byte_size(address), @max_address_bytes))
    else
      _ -> nil
    end
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} -> if String.downcase(to_string(key)) == name, do: value end)
  end
end
