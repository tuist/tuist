defmodule Pulse.Auth.Open do
  @moduledoc """
  No-auth implementation of `Pulse.Auth`. Accepts every request.

  Default for dev and test where the loopback-bound ingest port makes a
  real credential check net negative. Never suitable for a prod deployment
  reachable from the network.
  """

  @behaviour Pulse.Auth

  @impl Pulse.Auth
  def verify(_conn, _tenant), do: :ok
end
