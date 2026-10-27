defmodule AtlasWeb.AutomationController do
  use AtlasWeb, :controller

  alias Atlas.Automations.Interface

  @errors %{
    forbidden: {403, "forbidden"},
    not_found: {404, "not_found"},
    workflow_in_use: {409, "workflow_in_use"},
    workflow_changed: {409, "workflow_changed"},
    draft_changed: {409, "draft_changed"},
    not_published: {409, "not_published"},
    revision_changed: {409, "revision_changed"},
    idempotency_conflict: {409, "idempotency_conflict"},
    decision_not_allowed: {409, "decision_not_allowed"},
    invalid_execution_state: {409, "invalid_execution_state"},
    invalid_trigger_kind: {409, "invalid_trigger_kind"}
  }

  plug :private_response
  plug :require_access_token

  def action(conn, _) do
    conn = fetch_query_params(conn)
    operation = action_name(conn)

    if operation == :unsupported do
      unsupported(conn)
    else
      execute(conn, operation)
    end
  end

  defp execute(conn, operation) do
    with {:ok, args} <- arguments(conn, operation),
         {:ok, result} <- Interface.execute(operation, conn.assigns.current_user, args, interface: "api") do
      status =
        if operation in [:behavior, :trigger, :publish] or (operation == :save && conn.method == "POST"),
          do: 201,
          else: 200

      conn |> put_status(status) |> json(result)
    else
      {:error, reason} -> failure(conn, reason)
    end
  end

  defp arguments(conn, operation) do
    body = if conn.method == "GET", do: conn.query_params, else: conn.body_params

    if operation == :save && conn.request_path == "/api/automation/workflows" && Map.has_key?(body, "id") do
      {:error, :invalid_input}
    else
      args = body |> Map.merge(conn.path_params) |> Map.merge(conn.private[:automation_parameters] || %{})
      args = Enum.reduce(~w(page days), args, &integer_argument/2)
      {:ok, args}
    end
  end

  defp integer_argument(key, args) do
    case args[key] do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} -> Map.put(args, key, number)
          _ -> args
        end

      _ ->
        args
    end
  end

  defp failure(conn, reason) do
    {status, code} = Map.get(@errors, reason, {422, "invalid_input"})
    conn |> put_status(status) |> json(%{error: code})
  end

  defp unsupported(conn) do
    methods =
      Enum.filter(~w(GET POST PATCH DELETE), fn method ->
        case Phoenix.Router.route_info(AtlasWeb.Router, method, conn.request_path, conn.host) do
          %{plug: __MODULE__, plug_opts: operation} when operation != :unsupported -> true
          _ -> false
        end
      end)

    if methods == [] do
      failure(conn, :not_found)
    else
      conn
      |> put_resp_header("allow", Enum.join(methods, ", "))
      |> put_status(405)
      |> json(%{error: "use_primitive_lifecycle_operations"})
    end
  end

  defp require_access_token(conn, _) do
    if conn.assigns.mcp_claims["typ"] == "access_token",
      do: conn,
      else: conn |> put_status(401) |> json(%{error: "invalid_token"}) |> halt()
  end

  defp private_response(conn, _), do: put_resp_header(conn, "cache-control", "no-store")
end
