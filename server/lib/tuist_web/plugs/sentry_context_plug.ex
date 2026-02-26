defmodule TuistWeb.Plugs.SentryContextPlug do
  @moduledoc """
  A plug that sets Sentry context data based on the authenticated subject
  and selected resources. Only IDs are used to keep data anonymous.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    if Tuist.Environment.error_tracking_enabled?() do
      auth_data = get_auth_data(conn)
      set_sentry_context(auth_data)
    end

    auth_observability_data = get_auth_observability_data(conn)
    set_observability_context(auth_observability_data)

    conn
  end

  @doc """
  Sets Sentry context for the selected project and/or account.
  Call this after assigning :selected_project or :selected_account to the conn.
  """
  def set_selection_context(conn) do
    if Tuist.Environment.error_tracking_enabled?() do
      selection_data = get_selection_data(conn)
      set_sentry_context(selection_data)
    end

    selection_observability_data = get_selection_observability_data(conn)
    set_observability_context(selection_observability_data)

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

  defp get_auth_observability_data(conn) do
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

  defp get_selection_observability_data(conn) do
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

  defp set_sentry_context(context) when context == %{} do
    :ok
  end

  defp set_sentry_context(context) do
    Sentry.Context.set_extra_context(context)
  end

  defp set_observability_context(context) when context == %{} do
    :ok
  end

  defp set_observability_context(context) do
    Logger.metadata(context)

    Enum.each(context, fn {key, value} ->
      OpenTelemetry.Tracer.set_attribute(Atom.to_string(key), value)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
