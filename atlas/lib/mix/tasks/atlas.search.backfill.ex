defmodule Mix.Tasks.Atlas.Search.Backfill do
  @shortdoc "Backfills Atlas shared search records"

  @moduledoc """
  Backfills Atlas shared search records from existing prose-heavy resources.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, _invalid} =
      OptionParser.parse(args,
        strict: [no_embeddings: :boolean]
      )

    embed? = not Keyword.get(opts, :no_embeddings, false)

    {:ok, counts} = Atlas.Search.backfill(embed?: embed?)
    shell = Mix.shell()

    counts
    |> Enum.map(fn {source, count} -> "#{source}: indexed=#{count.indexed} failed=#{count.failed}" end)
    |> Enum.each(fn line -> shell.info(line) end)
  end
end
