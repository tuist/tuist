defmodule Atlas.MCP.Tools.SetOVHServerDisplayName do
  @moduledoc """
  Renames an OVH dedicated server's service, the step that releases a prepared
  box to a fleet.

  OVH's MCP servers expose no displayName write, so this calls OVH's REST API
  directly with the caller's own `ovh-services` OAuth session, the same identity
  the proxied OVH tools use. A matching name makes the fleet adopt and wipe the
  box, so every rename waits for the caller's approval of that exact call, like
  the gated reinstall.
  """

  use Atlas.MCP.Tool,
    name: "ovh_set_server_display_name",
    schema: %{
      "type" => "object",
      "required" => ["serviceName", "displayName"],
      "properties" => %{
        "serviceName" => %{
          "type" => "string",
          "pattern" => "^[A-Za-z0-9.-]+$",
          "description" => "The dedicated server's service name, for example `ns1030646.ip-40-160-26.us`."
        },
        "displayName" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 255,
          "description" => "The new displayName, for example the fleet's adoptDisplayNamePrefix."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["serviceName", "serviceId", "previousDisplayName", "displayName", "changed"],
      "properties" => %{
        "serviceName" => %{"type" => "string"},
        "serviceId" => %{"type" => "integer"},
        "previousDisplayName" => %{"type" => ["string", "null"]},
        "displayName" => %{"type" => "string"},
        "changed" => %{"type" => "boolean"}
      },
      "additionalProperties" => false
    }

  alias Atlas.MCP, as: MCPContext
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Tool
  alias Atlas.Users.User

  # The session and approval are recorded under this upstream, so the request
  # shows next to the other OVH tools at /admin/mcps.
  @server "ovh-services"
  @approval_tool "set-server-display-name"
  @api "https://api.us.ovhcloud.com/1.0"

  @impl EMCP.Tool
  def description do
    "[ovh-services] Set an OVH dedicated server's displayName through your own OVH connection. A name matching a " <>
      "fleet's adoptDisplayNamePrefix makes that fleet adopt and wipe the box, so each rename needs its own approval: " <>
      "the first call files a request and returns a link, the person approves it in Atlas, and the same call with " <>
      "identical arguments then runs once. A server that already has the name is left alone without approval."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "OVH renames"),
         :ok <- validate(args),
         {:ok, token} <- access_token(Tool.current_user(conn)),
         {:ok, service_id} <- service_id(token, args["serviceName"]),
         {:ok, previous} <- display_name(token, service_id) do
      result = %{
        serviceName: args["serviceName"],
        serviceId: service_id,
        previousDisplayName: previous,
        displayName: args["displayName"],
        changed: false
      }

      if previous == args["displayName"] do
        {:ok, result}
      else
        with :ok <- approve(conn, args),
             :ok <- rename(token, service_id, args["displayName"]) do
          {:ok, %{result | changed: true}}
        end
      end
    end
  end

  defp validate(args) do
    case ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(input_schema()), args) do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the #{name()} schema."}
    end
  end

  defp access_token(user) do
    with {:ok, server} <- Proxy.fetch_server(@server),
         {:ok, token} <- MCPContext.access_token_for(user, server) do
      {:ok, token}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, _reason} ->
        {:error, "Connect Atlas → #{@server} at #{AtlasWeb.Endpoint.url()}/admin/mcps, then retry."}
    end
  end

  defp approve(%{assigns: %{current_user: %User{} = user, audit_interface: "mcp"}}, args) do
    case MCPContext.authorize_tool_call(user, @server, @approval_tool, args) do
      {:ok, _approval} ->
        :ok

      {:approval_required, approval} ->
        {:error,
         "Renaming #{args["serviceName"]} to #{args["displayName"]} needs a person's approval for this exact call. " <>
           "Ask the person you are working for to approve request #{approval.id} at " <>
           "#{AtlasWeb.Endpoint.url()}/approvals/#{approval.id} " <>
           "(it expires at #{DateTime.to_iso8601(approval.expires_at)}), then repeat the call with identical arguments. " <>
           "Never approve it yourself."}
    end
  end

  defp approve(_conn, _args), do: {:error, "OVH renames need a person's approval and are only callable over Atlas MCP."}

  defp service_id(token, service_name) do
    case ovh(token, :get, "/dedicated/server/#{service_name}/serviceInfos") do
      {:ok, %{"serviceId" => id}} when is_integer(id) -> {:ok, id}
      {:ok, _body} -> {:error, "OVH returned no serviceId for #{service_name}."}
      error -> error
    end
  end

  # Read from /services/{id}, the endpoint the fleet's adoption scan uses. The
  # legacy /service/{id} kept returning the old name after a rename that
  # /services/{id} already showed.
  defp display_name(token, service_id) do
    with {:ok, body} <- ovh(token, :get, "/services/#{service_id}") do
      {:ok, get_in(body, ["resource", "displayName"])}
    end
  end

  # OVH answers the PUT with 200 whether or not the rename applied, and discards
  # it while a task such as a reinstall is still pending on the server, so the
  # name is read back instead of trusting the status.
  defp rename(token, service_id, name) do
    with {:ok, _body} <- ovh(token, :put, "/service/#{service_id}", %{"resource" => %{"displayName" => name}}),
         {:ok, ^name} <- display_name(token, service_id) do
      :ok
    else
      {:ok, observed} ->
        {:error,
         "OVH accepted the rename but the displayName is still #{inspect(observed)}. OVH drops renames while a task " <>
           "such as a reinstall is pending: wait for ovh-servers__list-dedicated-server-tasks to show none, then call " <>
           "again, which needs a new approval."}

      error ->
        error
    end
  end

  defp ovh(token, method, path, body \\ nil) do
    opts = [method: method, url: @api <> path, auth: {:bearer, token}, retry: false]
    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error,
         "OVH's API rejected your #{@server} session (HTTP #{status}) for #{method_label(method)} #{path}. " <>
           "Reconnect #{@server} at #{AtlasWeb.Endpoint.url()}/admin/mcps; if that does not help, this session " <>
           "cannot reach OVH's REST API and the rename has to go through baremetal:mark-ovh."}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "OVH returned HTTP #{status} for #{method_label(method)} #{path}: #{inspect(body)}"}

      {:error, _reason} ->
        {:error, "Could not reach OVH's API for #{method_label(method)} #{path}. Retry."}
    end
  end

  defp method_label(method), do: method |> Atom.to_string() |> String.upcase()
end
