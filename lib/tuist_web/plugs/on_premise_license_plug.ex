defmodule TuistWeb.OnPremiseLicensePlug do
  @moduledoc """
  This module contains plugs specific to on-premise customers.
  """
  import Plug.Conn
  use TuistWeb, :controller
  alias Tuist.Environment
  alias Tuist.License

  def init(:api), do: :api

  def call(conn, opts) do
    if Environment.on_premise?() do
      call_on_premise(conn, opts)
    else
      conn
    end
  end

  def call_on_premise(conn, _opts) do
    cond do
      License.valid?() and License.expiration_days_span() < 30 ->
        TuistWeb.WarningsHeaderPlug.put_warning(
          conn,
          "The license will expire in #{License.expiration_days_span()} days. Please, contact contact@tuist.io to renovate it."
        )

      not License.valid?() ->
        conn
        |> put_status(422)
        |> json(%{
          message: "The license has expired. Please, contact contact@tuist.io to renovate it."
        })
        |> halt()

      true ->
        conn
    end
  end
end
