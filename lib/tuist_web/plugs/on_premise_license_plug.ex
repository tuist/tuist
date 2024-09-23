defmodule TuistWeb.OnPremiseLicensePlug do
  @moduledoc """
  This module contains plugs specific to on-premise customers.
  """
  import Plug.Conn
  use TuistWeb, :controller
  alias Tuist.Environment
  alias Tuist.License
  alias Tuist.Time

  def init(:api), do: :api

  def call(conn, opts) do
    if Environment.on_premise?() do
      call_on_premise(conn, opts)
    else
      conn
    end
  end

  def call_on_premise(conn, _opts) do
    case License.get_license() do
      {:ok, %{valid: true, expiration_date: expiration_date}} ->
        if Date.diff(expiration_date, Time.utc_now()) < 30 do
          TuistWeb.WarningsHeaderPlug.put_warning(
            conn,
            "The license will expire in #{DateTime.diff(expiration_date, Time.utc_now(), :day)} days. Please, contact contact@tuist.io to renovate it."
          )
        else
          conn
        end

      {:ok, %{valid: true}} ->
        conn

      _ ->
        conn
        |> put_status(422)
        |> json(%{
          message: "The license has expired. Please, contact contact@tuist.io to renovate it."
        })
        |> halt()
    end
  end
end
