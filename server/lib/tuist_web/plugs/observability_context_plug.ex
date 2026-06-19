defmodule TuistWeb.Plugs.ObservabilityContextPlug do
  @moduledoc """
  A plug that sets request observability context in logger metadata and OTel span attributes.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    auth_data = get_auth_data(conn)
    set_context(auth_data)

    conn
  end

  @doc """
  Sets observability context for the selected project and/or account.
  Call this after assigning :selected_project or :selected_account to the conn.
  """
  def set_selection_context(conn) do
    selection_data = get_selection_data(conn)
    set_context(selection_data)

    conn
  end

  defp get_auth_data(conn) do
    case TuistWeb.Authentication.authenticated_subject(conn) do
      %User{account: %{name: account_handle}} ->
        %{auth_account_handle: account_handle}

      %Project{account: %{name: account_handle}} ->
        %{auth_account_handle: account_handle}

      %AuthenticatedAccount{account: %{name: account_handle}} ->
        %{auth_account_handle: account_handle}

      nil ->
        %{}
    end
  end

  defp get_selection_data(conn) do
    case {conn.assigns[:selected_project], conn.assigns[:selected_account]} do
      {%{name: project_handle}, %{name: account_handle}} ->
        %{
          selected_account_handle: account_handle,
          selected_project_handle: project_handle
        }

      {%{name: project_handle, account: %{name: account_handle}}, _} ->
        %{
          selected_account_handle: account_handle,
          selected_project_handle: project_handle
        }

      {_, %{name: account_handle}} ->
        %{selected_account_handle: account_handle}

      _ ->
        %{}
    end
  end

  defp set_context(context) when context == %{} do
    :ok
  end

  defp set_context(context) do
    Logger.metadata(context)

    Enum.each(context, fn {key, value} ->
      OpenTelemetry.Tracer.set_attribute(Atom.to_string(key), value)
    end)
  end
end
