defmodule Mix.Tasks.Luft.Workspace.Serve do
  @shortdoc "Serve an installed workspace on loopback with an ephemeral preview token"
  use Mix.Task

  alias LuftServer.Workspaces.Definition
  alias LuftServer.Workspaces.Local
  alias LuftServer.Workspaces.Preview
  alias Mix.Tasks.Luft.Workspace.Publish

  @impl true
  def run(args) do
    {options, [], []} =
      OptionParser.parse(args,
        strict: [database: :string, port: :integer, connection_file: :string, mcp_action: :keep]
      )

    path = options |> Keyword.fetch!(:connection_file) |> Path.expand()
    port = Keyword.get(options, :port, 4210)
    Definition.ensure!(port in 1024..65_535, "Invalid preview port")
    connection = Publish.connect!(options)
    {:ok, %{"organization" => organization, "actions" => actions}} = Local.workspace(connection)
    mcp_actions = Keyword.get_values(options, :mcp_action)

    Definition.ensure!(
      Enum.all?(mcp_actions, &Map.has_key?(actions, &1)),
      "Unknown MCP action grant"
    )

    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    Application.ensure_all_started(:bandit)

    {:ok, server} =
      Bandit.start_link(
        # Supervisor crash reports include plug options. Retain only the digest,
        # never the bearer credential, in the server's process configuration.
        plug:
          {Preview,
           connection: connection,
           token_hash: :crypto.hash(:sha256, token),
           mcp_actions: mcp_actions},
        ip: {127, 0, 0, 1},
        port: port
      )

    # Create exclusively with owner-only permissions, never truncate a symlink
    # or briefly expose a credential through a world-readable file.
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :exclusive, :raw, :binary])
    :ok = File.chmod(path, 0o600)
    :ok = :file.write(file, Jason.encode!(%{url: "http://127.0.0.1:#{port}", token: token}))
    :ok = :file.close(file)

    Mix.shell().info(
      "Local workspace #{organization} listening on loopback port #{port}; connection saved to #{path}"
    )

    try do
      Process.sleep(:infinity)
    after
      File.rm(path)
      GenServer.stop(server)
      GenServer.stop(connection)
    end
  end
end
