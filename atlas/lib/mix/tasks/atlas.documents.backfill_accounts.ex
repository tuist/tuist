defmodule Mix.Tasks.Atlas.Documents.BackfillAccounts do
  @shortdoc "Backfills Atlas account associations for ready documents"

  @moduledoc """
  Backfills account associations for existing ready documents.

      mix atlas.documents.backfill_accounts
      mix atlas.documents.backfill_accounts --limit 100
  """

  use Mix.Task

  alias Atlas.Documents

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    result = Documents.backfill_document_accounts(opts)

    Mix.shell().info(
      "Backfilled document account associations: matched=#{result.matched} unmatched=#{result.unmatched} failed=#{result.failed}"
    )
  end

  defp parse_args(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [limit: :integer])
    opts
  end
end
