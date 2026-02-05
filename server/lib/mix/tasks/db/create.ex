defmodule Mix.Tasks.Db.Create do
  @moduledoc ~S"""
  This task extends the ecto.create task to ensure all repos are started after database creation.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  import Mix.Ecto

  def run(args) do
    Mix.Tasks.Ecto.Create.run(args)

    # We need to start the app to be able to access the repository
    Mix.Task.run("app.start")

    repos = parse_repo(args)

    for repo <- repos do
      ensure_repo(repo, args)
    end
  end
end
