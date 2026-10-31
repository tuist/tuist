defmodule Tuist.Sandboxes.Workers.ArchiveSandboxesWorker do
  @moduledoc """
  Moves Amp Orbs paused longer than the archive threshold off their nodes
  into object storage, and cleans up archives of restored Orbs and uploads
  or restores whose caller died (`Tuist.Sandboxes.Archives.run/0`). An
  archive can take minutes, so a run still executing makes the next one a
  no-op.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [states: [:available, :scheduled, :executing], period: :infinity]

  alias Tuist.Sandboxes.Archives

  @impl Oban.Worker
  def perform(_job) do
    Archives.run()
    :ok
  end
end
