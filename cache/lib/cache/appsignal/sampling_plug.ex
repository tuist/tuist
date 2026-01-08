defmodule Cache.Appsignal.SamplingPlug do
  @moduledoc """
  A Plug that implements sampling for AppSignal transactions.
  AppSignal bills for APM for every request, not just errors, so sampling
  can help reduce costs, while still capturing all errors.

  - All errors (HTTP status >= 400) are always sent to AppSignal
  - 10% of successful requests are sampled
  """

  @behaviour Plug

  @sample_rate 0.1

  def init(opts), do: opts

  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, fn conn ->
      apply_sampling(conn)
      conn
    end)
  end

  defp apply_sampling(conn) do
    cond do
      conn.status >= 400 -> :ok
      :rand.uniform() < @sample_rate -> :ok
      true -> Appsignal.Tracer.ignore()
    end
  end
end
