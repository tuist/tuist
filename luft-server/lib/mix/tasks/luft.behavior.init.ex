defmodule Mix.Tasks.Luft.Behavior.Init do
  @shortdoc "Provision a disposable behavior database and explicit local principal grants"
  use Mix.Task

  alias LuftServer.Workspaces.Behaviors
  alias LuftServer.Workspaces.Local

  @impl true
  def run(args) do
    {options, [], []} =
      OptionParser.parse(args,
        strict: [
          database: :string,
          organization: :integer,
          account: :integer,
          principals: :string
        ]
      )

    Mix.Task.run("app.start")
    principals = options |> Keyword.fetch!(:principals) |> File.read!() |> Jason.decode!()
    principals = Map.new(principals, fn {id, grants} -> {String.to_integer(id), grants} end)
    connection = Local.connect!(Keyword.fetch!(options, :database), true)

    try do
      {:ok, :ok} =
        Behaviors.initialize(
          connection,
          Keyword.fetch!(options, :organization),
          Keyword.fetch!(options, :account),
          principals
        )

      Mix.shell().info(
        "Disposable behavior database initialized. No release was approved or activated."
      )
    after
      GenServer.stop(connection)
    end
  end
end
