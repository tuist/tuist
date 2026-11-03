defmodule Tuist.Sandboxes.Workers.ArchiveSandboxesWorker do
  @moduledoc """
  Moves Amp Orbs paused longer than the archive threshold, or past their
  account's on-node cap, off their nodes into object storage, and cleans up
  archives of restored Orbs and uploads or restores whose caller died
  (`Tuist.Sandboxes.Archives.run/0`). An archive can take minutes, so at
  most one run waits behind the one executing; the sandbox lock and the
  upload marker keep two runs off the same Orb.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [states: [:available, :scheduled], period: :infinity]

  alias Tuist.Sandboxes.Archives

  @impl Oban.Worker
  def perform(_job) do
    Archives.run()
    :ok
  end
end
