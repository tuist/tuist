defmodule Mix.Tasks.Luft.Workspace.Seed do
  @shortdoc "Load fictional fixtures into an empty local workspace"
  use Mix.Task

  alias LuftServer.Workspaces.Local
  alias Mix.Tasks.Luft.Workspace.Publish

  @impl true
  def run(args) do
    {options, [path], []} = OptionParser.parse(args, strict: [database: :string])
    connection = Publish.connect!(options)

    try do
      {:ok, count} = Local.seed(connection, path)
      Mix.shell().info("Seeded #{count} local fixture records")
    after
      GenServer.stop(connection)
    end
  end
end
