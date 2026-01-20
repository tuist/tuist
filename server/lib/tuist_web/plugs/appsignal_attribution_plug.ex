defmodule TuistWeb.Plugs.AppsignalAttributionPlug do
  @moduledoc """
  A plug that sets AppSignal attribution data based on the authenticated subject
  and selected resources. Only IDs are used to keep data anonymous.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  def init(opts), do: opts

  def call(conn, _opts) do
    if Tuist.Environment.error_tracking_enabled?() do
      span = Appsignal.Tracer.root_span()
      auth_data = get_auth_data(conn)
      set_tags(span, auth_data)
    end

    conn
  end

  @doc """
  Sets AppSignal tags for the selected project and/or account.
  Call this after assigning :selected_project or :selected_account to the conn.
  """
  def set_selection_tags(conn) do
    if Tuist.Environment.error_tracking_enabled?() do
      span = Appsignal.Tracer.root_span()
      selection_data = get_selection_data(conn)
      set_tags(span, selection_data)
    end

    conn
  end

  defp get_auth_data(conn) do
    case TuistWeb.Authentication.authenticated_subject(conn) do
      %User{id: user_id, account: %{id: account_id, name: account_handle}} ->
        %{
          auth_user_id: user_id,
          auth_account_id: account_id,
          auth_account_handle: account_handle
        }

      %Project{id: project_id, account: %{id: account_id, name: account_handle}} ->
        %{
          auth_project_id: project_id,
          auth_account_id: account_id,
          auth_account_handle: account_handle
        }

      %AuthenticatedAccount{account: %{id: account_id, name: account_handle}} ->
        %{auth_account_id: account_id, auth_account_handle: account_handle}

      nil ->
        %{}
    end
  end

  defp get_selection_data(conn) do
    case {conn.assigns[:selected_project], conn.assigns[:selected_account]} do
      {%{id: project_id, name: project_handle}, %{id: account_id, name: account_handle, customer_id: customer_id}} ->
        maybe_put(
          %{
            selected_project_id: project_id,
            selected_project_handle: project_handle,
            selected_account_id: account_id,
            selected_account_handle: account_handle
          },
          :selected_account_customer_id,
          customer_id
        )

      {_, %{id: account_id, name: account_handle, customer_id: customer_id}} ->
        maybe_put(
          %{selected_account_id: account_id, selected_account_handle: account_handle},
          :selected_account_customer_id,
          customer_id
        )

      _ ->
        %{}
    end
  end

  defp set_tags(_span, tags) when tags == %{} do
    :ok
  end

  defp set_tags(span, tags) do
    Appsignal.Span.set_sample_data(span, "tags", tags)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
