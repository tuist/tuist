defmodule Mix.Tasks.Tuist.Setup do
  @shortdoc "Set up Tuist caching, build insights and test insights"

  @moduledoc """
  Configure dependency caching, build insights and test insights in the current Mix project.

      mix tuist.setup --project account/project

  Preserves project settings and aliases, including Phoenix test preparation.
  Unsupported custom compile/test actions need manual integration. Commit the updated mix.exs so CI and fresh checkouts use
  the same setup, then continue using mix compile and mix test.
  """

  use Mix.Task

  alias TuistEx.ProjectSetup

  def run(args) do
    {options, rest, invalid} = OptionParser.parse(args, strict: [project: :string])

    if rest != [] or invalid != [] do
      Mix.raise("Usage: mix tuist.setup [--project account/project]")
    end

    Mix.Project.with_build_lock(fn ->
      file = Mix.Project.project_file()

      if File.lstat!(file).type != :regular,
        do: Mix.raise("mix.exs must be a regular file. No changes were made.")

      source = File.read!(file)

      case ProjectSetup.configure(source, Mix.Project.config(), options) do
        {:ok, ^source} ->
          Mix.shell().info("Tuist is already configured.")

        {:ok, updated} ->
          temporary = "#{file}.tuist-#{System.pid()}-#{System.unique_integer([:positive])}"

          try do
            File.write!(temporary, updated)
            File.chmod!(temporary, File.stat!(file).mode)

            if File.read!(file) != source,
              do: Mix.raise("mix.exs changed during setup. Run mix tuist.setup again.")

            File.rename!(temporary, file)
          after
            File.rm(temporary)
          end

          Mix.shell().info(
            "Updated mix.exs. Commit it, then keep using mix compile and mix test."
          )

        {:error, message} ->
          Mix.raise(message)
      end
    end)
  end
end
