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

      auth_data =
        case TuistWeb.Authentication.authenticated_subject(conn) do
          %User{id: user_id, account: %{id: account_id, name: account_handle}} ->
            %{user_id: user_id, account_id: account_id, account_handle: account_handle}

          %Project{id: project_id, account: %{id: account_id, name: account_handle}} ->
            %{project_id: project_id, account_id: account_id, account_handle: account_handle}

          %AuthenticatedAccount{account: %{id: account_id, name: account_handle}} ->
            %{account_id: account_id, account_handle: account_handle}

          nil ->
            %{}
        end

      selection_data =
        case {conn.assigns[:selected_project], conn.assigns[:selected_account]} do
          {%{id: project_id, name: project_handle}, %{id: account_id, name: account_handle}} ->
            %{
              project_id: project_id,
              project_name: project_handle,
              account_id: account_id,
              account_handle: account_handle
            }

          {_, %{id: account_id, name: account_handle}} ->
            %{account_id: account_id, account_handle: account_handle}

          _ ->
            %{}
        end

      custom_data =
        %{}
        |> maybe_put(:auth, auth_data)
        |> maybe_put(:selection, selection_data)

      set_sample_data(span, "custom_data", custom_data)
    end

    conn
  end

  defp set_sample_data(_span, _key, data) when data == %{} do
    :ok
  end

  defp set_sample_data(span, key, data) do
    Appsignal.Span.set_sample_data(span, key, data)
  end

  defp maybe_put(map, _key, value) when value == %{}, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
