defmodule TuistWeb.API.PulseController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Pulse
  alias Tuist.Pulse.Schemas
  alias TuistWeb.API.Schemas.Error

  plug :no_store
  plug :validate_query_keys
  plug TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug

  tags ["Pulse"]

  @operations Map.new(
                [
                  {:query, "queryPulse", "Query, filter, sort and paginate a Pulse signal."},
                  {:analytics, "getPulseAnalytics", "Get fixed Pulse aggregate widgets, independent of table filters."}
                ],
                fn {action, operation_id, summary} ->
                  {action,
                   [
                     summary: summary,
                     operation_id: operation_id,
                     parameters: Schemas.parameters(action),
                     responses: %{
                       ok: {"Pulse data", "application/json", Schemas.response(action)},
                       bad_request: {"Invalid parameters or query", "application/json", Error},
                       unauthorized: {"Authentication required", "application/json", Error},
                       forbidden: {"User membership and account read required", "application/json", Error},
                       not_found: {"Account not found", "application/json", Error},
                       too_many_requests: {"Pulse rate limited", "application/json", Error},
                       service_unavailable:
                         {"Pulse unavailable or query result limit exceeded", "application/json", Error}
                     }
                   ]}
                end
              )

  operation(:query, @operations[:query])
  operation(:analytics, @operations[:analytics])

  for action <- [:query, :analytics] do
    def unquote(action)(conn, params) do
      params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

      with %User{} = user <- credential_user(conn.assigns),
           account when not is_nil(account) <- Accounts.get_account_by_handle(params["account_handle"]),
           :ok <- Authorization.authorize(:account_dashboard_read, user, account),
           true <- Pulse.authorized?(user, account) do
        options = Map.drop(params, ~w(account_handle signal))

        result =
          case unquote(action) do
            :query -> Pulse.query(user, account, params["signal"], options)
            :analytics -> Pulse.analytics(user, account, params["signal"], options)
          end

        respond(conn, result)
      else
        nil -> respond(conn, {:error, :not_found})
        _ -> respond(conn, {:error, :forbidden})
      end
    end
  end

  defp credential_user(%{current_user: %User{id: id} = user} = assigns) do
    # User associations for OAuth/MCP credentials belong to /mcp, not the REST API.
    # Do not let current_user hide an independently authenticated scoped subject.
    case assigns[:current_subject] || user do
      %User{id: ^id} ->
        user

      _ ->
        :forbidden
    end
  end

  defp credential_user(_), do: :forbidden

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "private, no-store")

  defp validate_query_keys(conn, _opts) do
    allowed = conn |> action_name() |> Schemas.options() |> Map.keys() |> Enum.map(&to_string/1)

    if Enum.all?(Map.keys(conn.query_params), &(&1 in allowed)),
      do: conn,
      else: conn |> respond({:error, :invalid_params}) |> halt()
  end

  defp respond(conn, {:ok, data}), do: json(conn, data)

  defp respond(conn, {:error, reason}) do
    {status, message} =
      case reason do
        :forbidden ->
          {:forbidden,
           "Pulse requires a user credential with account-read access and current membership in the configured organization."}

        :not_found ->
          {:not_found, "Pulse account not found."}

        :invalid_params ->
          {:bad_request, "Invalid Pulse parameters, filters, sorting or pagination."}

        :invalid_query ->
          {:bad_request, "Invalid Pulse query."}

        :rate_limited ->
          {:too_many_requests, "Pulse is rate limited. Try again later."}

        :query_result_limit ->
          {:service_unavailable, "Pulse query exceeded its result limit. Narrow the query or time range."}

        _ ->
          {:service_unavailable, "Pulse is temporarily unavailable."}
      end

    conn |> put_status(status) |> json(%{message: message})
  end
end
