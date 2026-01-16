defmodule TuistWeb.Plugs.AppsignalSamplingPlug do
  @moduledoc """
  A Plug that implements sampling for AppSignal transactions.
  AppSignal bills for APM for every request, not just errors, so sampling
  can help reduce costs, while still capturing all errors.

  This plug only samples requests to specific controllers (e.g., CacheController).
  All other requests are always traced.

  For sampled controllers:
  - All errors (HTTP status >= 400) are always sent to AppSignal
  - 10% of successful requests are sampled
  """

  @behaviour Plug

  @sample_rate 0.1

  @sampled_controllers [
    TuistWeb.API.CacheController
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, fn conn ->
      apply_sampling(conn)
      conn
    end)
  end

  defp apply_sampling(conn) do
    controller = conn.private[:phoenix_controller]

    if controller in @sampled_controllers do
      sample_request(conn)
    else
      :ok
    end
  end

  defp sample_request(conn) do
    cond do
      conn.status >= 400 -> :ok
      :rand.uniform() < @sample_rate -> :ok
      true -> Appsignal.Tracer.ignore()
    end
  end
end
