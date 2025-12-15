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
          %User{id: user_id, account: %{id: account_id}} ->
            %{user_id: user_id, account_id: account_id}

          %Project{id: project_id, account: %{id: account_id}} ->
            %{project_id: project_id, account_id: account_id}

          %AuthenticatedAccount{account: %{id: account_id}} ->
            %{account_id: account_id}

          nil ->
            %{}
        end

      set_sample_data(span, "auth", auth_data)

      selection_data =
        case {conn.assigns[:selected_project], conn.assigns[:selected_account]} do
          {%{id: project_id}, %{id: account_id}} ->
            %{project_id: project_id, account_id: account_id}

          {_, %{id: account_id}} ->
            %{account_id: account_id}

          _ ->
            %{}
        end

      set_sample_data(span, "selection", selection_data)
    end

    conn
  end

  defp set_sample_data(_span, _key, %{} = _data) do
  end

  defp set_sample_data(span, key, data) do
    Appsignal.Span.set_sample_data(span, key, data)
  end
end
