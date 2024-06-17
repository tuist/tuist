defmodule TuistCloudWeb.RateLimit do
  @moduledoc """
  A module that provides functions for rate limiting requests.
  """
  alias TuistCloud.Environment

  def rate_limit(%Plug.Conn{} = conn, _opts) do
    if Environment.on_premise?() do
      conn
    else
      case Hammer.check_rate(TuistCloudWeb.RemoteIp.get(conn), 60_000, 1_000) do
        {:allow, _count} ->
          conn

        {:deny, _limit} ->
          raise TuistCloudWeb.Errors.TooManyRequestsError,
            message: "You have made too many requests. Please try again later."
      end
    end
  end
end
