defmodule TuistWeb.Plugs.PulseRoutesPlug do
  @moduledoc """
  Keeps links working around the account-level Pulse pages.

  - `:legacy` permanently redirects the former `/:account/~/pulse/*` paths.
  - `:project_fallback` runs ahead of the Pulse pages' authentication.
    `/:account/pulse` used to show a project named `pulse`, a handle now
    reserved. For an account Pulse doesn't run for, such a project keeps its
    overview at `/:account/pulse/analytics`, the same page.
  """
  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Pulse

  def init(action), do: action

  def call(%{path_info: [account_handle, "~", "pulse" | rest]} = conn, :legacy) do
    redirect_to(conn, :moved_permanently, [account_handle, "pulse" | rest])
  end

  def call(%{path_info: [account_handle, "pulse"]} = conn, :project_fallback) do
    with %Account{} = account <- Accounts.get_account_by_handle(account_handle),
         false <- Pulse.available?(account),
         %Project{} <- Projects.get_project_by_account_and_project_handles(account_handle, "pulse") do
      redirect_to(conn, :found, [account_handle, "pulse", "analytics"])
    else
      _ -> conn
    end
  end

  def call(conn, _action), do: conn

  defp redirect_to(conn, status, segments) do
    # `path_info` keeps the request's percent-encoding.
    path = "/" <> Enum.join(segments, "/")
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_status(status)
    |> redirect(to: path)
    |> halt()
  end
end
