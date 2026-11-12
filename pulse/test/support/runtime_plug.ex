defmodule Pulse.Test.RuntimePlug do
  @moduledoc """
  Serves a plug from a real HTTP server under a test-owned runtime.

  Server connection processes are not descendants of the test, so the test's
  runtime is captured explicitly and installed before every request.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    plug = Keyword.fetch!(opts, :plug)
    Pulse.Runtime.install(Keyword.fetch!(opts, :runtime))
    plug.call(conn, plug.init(Keyword.get(opts, :plug_opts, [])))
  end
end
