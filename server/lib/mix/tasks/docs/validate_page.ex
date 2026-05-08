defmodule Mix.Tasks.Docs.ValidatePage do
  @shortdoc "Validates a documentation Markdown page"

  @moduledoc """
  Validates that a documentation Markdown page can be parsed and rendered.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.Mix

  alias Tuist.Docs.Loader

  @impl Mix.Task
  def run([path]) do
    path
    |> Path.expand(File.cwd!())
    |> Loader.validate_page!()

    Mix.shell().info("Validated docs page #{path}")
  end

  def run(_args) do
    Mix.raise("Usage: mix docs.validate_page PATH")
  end
end
