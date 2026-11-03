defmodule Mix.Tasks.Atlas.Orbit.BackfillDomains do
  @shortdoc "Queues missing domain labels for existing Orbit conversations"

  @moduledoc """
  Backfills unlabeled active and archived threads using their owner's configured
  Orbit provider and current read access. Existing labels and recency are preserved.
  Only nonempty human messages or signal evidence are used, never private catch-ups.
  Repeated invocations reuse incomplete classification jobs.

      mix atlas.orbit.backfill_domains --dry-run
      mix atlas.orbit.backfill_domains --limit 100
      mix atlas.orbit.backfill_domains

  `--dry-run` only counts candidates; it neither queues jobs nor calls a model.
  `--limit` bounds the number of candidates scanned, including inaccessible or
  unconfigured owners. Without it, all candidates are scanned in 100-thread batches.
  Applying the backfill queues asynchronous inference and may incur provider usage.
  """

  use Mix.Task

  alias Atlas.Orbit.Classification

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [dry_run: :boolean, limit: :integer])

    if rest != [] or (opts[:limit] != nil and opts[:limit] <= 0) do
      Mix.raise("Expected --dry-run and/or --limit with a positive integer")
    end

    Mix.Task.run("app.start")
    counts = Classification.backfill(opts)
    mode = if opts[:dry_run], do: "Dry run", else: "Backfill queued"

    Mix.shell().info("#{mode}: scanned=#{counts.scanned} eligible=#{counts.eligible} enqueued=#{counts.enqueued}")
  end
end
