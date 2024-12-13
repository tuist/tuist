defmodule TuistWeb.API.EnsureAccountPresencePlug do
  @moduledoc ~S"""
  A plug that ensures the presence of an account identified through the request
  parameters. When the request is absent, it returns a 404 response.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Accounts

  def init(opts), do: opts

  def call(
        %{
          params: %{
            "account_handle" => account_handle
          }
        } = conn,
        _opts
      ) do
    case Accounts.get_account_by_handle(account_handle) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{message: "The account #{account_handle} was not found."})
        |> halt()

      account ->
        conn |> assign(:url_account, account)
    end
  end
end
