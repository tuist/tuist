defmodule Mix.Tasks.Luft.Workspace.Publish do
  @shortdoc "Install a local workspace into disposable PostgreSQL (not production)"
  @moduledoc """
  mix luft.workspace.publish path/to/workspace.json --database luft_workspace_demo

  Installs typed tables and the UI bundle atomically. Repeating an identical
  publication is safe. The pilot supports new models and additive fields with
  explicit version increments, not destructive or arbitrary SQL migrations.
  """
  use Mix.Task

  alias LuftServer.Workspaces.Local

  @impl true
  def run(args) do
    {options, [path], []} = OptionParser.parse(args, strict: [database: :string])
    connection = connect!(options, true)

    try do
      {:ok, result} = Local.publish(connection, path)
      Mix.shell().info("Published local workspace: #{Jason.encode!(result)}")
    after
      GenServer.stop(connection)
    end
  end

  @doc false
  def connect!(options, create? \\ false) do
    if Mix.env() == :prod, do: Mix.raise("Local workspace tasks are disabled in production")
    Mix.Task.run("app.config")
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto)
    Application.ensure_all_started(:jason)
    Local.connect!(Keyword.fetch!(options, :database), create?)
  end
end
