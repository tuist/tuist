defmodule TuistWeb.RateLimit do
  @moduledoc """
  A module that provides functions for rate limiting requests.
  """
  use Hammer, backend: :ets
  alias Tuist.Environment

  def rate_limit(%Plug.Conn{} = conn, _opts) do
    if Environment.on_premise?() do
      conn
    else
      scale_ms = :timer.minutes(1)
      limit = 1_000

      case hit(TuistWeb.RemoteIp.get(conn), scale_ms, limit) do
        {:allow, _count} ->
          conn

        {:deny, _limit} ->
          raise TuistWeb.Errors.TooManyRequestsError,
            message: "You have made too many requests. Please try again later."
      end
    end
  end
end
