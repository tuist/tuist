defmodule Condukt.MCP do
  @moduledoc """
  Client-side support for the [Model Context Protocol](https://modelcontextprotocol.io).

  Condukt agents can declare external MCP servers and call the tools those
  servers expose alongside their own statically defined tools. Each declared
  server is started as a supervised `Condukt.MCP.Client` process for the
  lifetime of the session, the server's `tools/list` is fetched, and each
  remote tool is exposed to the model as a prefixed entry in the tool registry
  (`<server>.<tool>` by default).

  ## Declaring servers on an agent

  Add an optional `mcp_servers/0` function to a module that uses
  `Condukt`. Return a list of `Condukt.MCP.Server` structs or maps
  describing the transport and (for HTTP transports) authentication.

      defmodule MyApp.Agent do
        use Condukt

        @impl true
        def tools do
          [Condukt.Tools.Read, Condukt.Tools.Bash]
        end

        def mcp_servers do
          [
            %Condukt.MCP.Server{
              name: "github",
              transport: {:stdio, command: "github-mcp-server", args: []},
              env: ["GITHUB_TOKEN"]
            },
            %Condukt.MCP.Server{
              name: "linear",
              transport: {:streamable_http, url: "https://mcp.linear.app/mcp"},
              auth: {:bearer, {:env, "LINEAR_API_KEY"}}
            }
          ]
        end
      end

  Servers can also be supplied per-call through the `:mcp_servers` option
  on `Condukt.run/3` and through an agent module's `start_link/1`.

  ## Authentication

  v1 supports two HTTP authentication modes declared on the server:

    * `{:bearer, secret_ref}` adds an `Authorization: Bearer <token>`
      header. The secret reference uses the same shape as
      `Condukt.Secrets` entries: `{:env, "NAME"}`, `{:static, "value"}`,
      `{:op, "op://..."}`, or `{provider_module, opts}`.
    * `{:client_credentials, opts}` performs an OAuth 2.0 client
      credentials grant against `:token_url` using `:client_id`/`:client_secret`
      (or `_env` variants) and caches the access token until a request
      fails with `401`, at which point it refreshes once.

  Interactive OAuth flows that require a browser are intentionally not
  supported by the headless library. Resolve such tokens out of band
  (for example via a separate one-time CLI login) and surface the
  resulting refresh or access token through one of the provider shapes
  above.

  For stdio transports the `:auth` field is unused; credentials flow
  into the spawned subprocess as environment variables declared on the
  server's `:env` field.

  ## Sandbox interaction

  Stdio MCP servers are user-configured external binaries that Condukt
  spawns as part of session setup. They are not routed through
  `Condukt.Sandbox` for the same reason `Condukt.Tools.Command` is
  exempt: the binary is selected by the operator, not by the model.
  HTTP and streamable HTTP transports issue plain HTTP requests through
  Req and have nothing to sandbox.
  """

  alias Condukt.MCP.{Client, Registry, Server}

  @doc """
  Starts an MCP client for the given server spec.

  This returns once the `initialize` handshake and `tools/list` exchange
  have completed. Use `Condukt.MCP.Client.call_tool/4` to invoke tools
  on the connected server.
  """
  def start_link(%Server{} = server, opts \\ []) do
    Client.start_link(server, opts)
  end

  @doc """
  Starts a list of MCP clients in parallel and returns a registry value
  describing the running connections and the tools they expose.

  The return value is opaque; pass it to `Condukt.MCP.Registry.tools/1`
  to obtain the list of inline tool specs ready to be merged into an
  agent tool list, and to `Condukt.MCP.Registry.stop_all/1` for
  cleanup.
  """
  defdelegate start_all(servers, opts \\ []), to: Registry, as: :start_all

  @doc """
  Stops the connections held by a registry value returned by `start_all/2`.
  """
  defdelegate stop_all(registry), to: Registry, as: :stop_all

  @doc """
  Returns the inline `Condukt.Tool` specs for every tool exposed by the
  servers in a registry.
  """
  defdelegate tools(registry), to: Registry, as: :tools
end
