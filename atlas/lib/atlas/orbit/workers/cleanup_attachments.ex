defmodule Atlas.Orbit.Workers.CleanupAttachments do
  @moduledoc """
  Reclaims abandoned uploads after 24 hours and deletes discarded/orphaned
  objects. Rows remain as a cleanup ledger until storage confirms deletion.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Orbit.Attachments

  @impl Oban.Worker
  def perform(_job), do: Attachments.cleanup()
end
