defmodule Mix.Tasks.Atlas.Inbox.ReprocessFailed do
  @shortdoc "Re-enqueues IngestEmail for inbox_emails currently in `failed`"

  @moduledoc """
  One-shot backfill: enqueues an `IngestEmail` job for every inbox_email
  whose status is `failed`, so an inbox-pipeline fix can pick them up.

      mix atlas.inbox.reprocess_failed
  """

  use Mix.Task

  alias Atlas.Inbox

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    %{enqueued: count} = Inbox.reenqueue_failed()

    Mix.shell().info("Re-enqueued IngestEmail for #{count} failed inbox_email(s)")
  end
end
