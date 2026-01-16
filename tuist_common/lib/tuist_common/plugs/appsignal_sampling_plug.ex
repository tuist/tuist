defmodule TuistCommon.Plugs.AppsignalSamplingPlug do
  @moduledoc """
  A Plug that implements sampling for AppSignal transactions.
  AppSignal bills for APM for every request, not just errors, so sampling
  can help reduce costs, while still capturing all errors.

  - All errors (HTTP status >= 400) are always sent to AppSignal
  - 10% of successful requests are sampled

  When `:sampled_controllers` is specified, only requests to those controllers
  are sampled. All other requests are always traced.
  """

  @behaviour Plug

  @sample_rate 0.1

  defstruct sampled_controllers: []

  def init(opts), do: struct!(__MODULE__, opts)

  def call(conn, %__MODULE__{sampled_controllers: []}) do
    Plug.Conn.register_before_send(conn, fn conn ->
      apply_sampling(conn)
      conn
    end)
  end

  def call(conn, %__MODULE__{sampled_controllers: sampled_controllers}) do
    Plug.Conn.register_before_send(conn, fn conn ->
      controller = conn.private[:phoenix_controller]

      if controller in sampled_controllers do
        apply_sampling(conn)
      else
        :ok
      end

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
