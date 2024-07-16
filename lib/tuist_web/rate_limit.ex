defmodule TuistWeb.RateLimit do
  @moduledoc """
  A module that provides functions for rate limiting requests.
  """
  alias Tuist.Environment

  def rate_limit(%Plug.Conn{} = conn, _opts) do
    if Environment.on_premise?() do
      conn
    else
      case Hammer.check_rate(TuistWeb.RemoteIp.get(conn), 60_000, 1_000) do
        {:allow, _count} ->
          conn

        {:deny, _limit} ->
          raise TuistWeb.Errors.TooManyRequestsError,
            message: "You have made too many requests. Please try again later."
      end
    end
  end
end
