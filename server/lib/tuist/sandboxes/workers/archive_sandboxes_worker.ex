defmodule Tuist.Sandboxes.Workers.ArchiveSandboxesWorker do
  @moduledoc """
  Moves Amp Orbs paused longer than the archive threshold off their nodes
  into object storage, and cleans up
  archives of restored Orbs and uploads or restores whose caller died
  (`Tuist.Sandboxes.Archives.run/0`). A job with an `account_id` instead
  archives that account's least recently paused idle Orb to make room under
  its disk limit (`Archives.make_room/1`). An archive can take minutes, so at
  most one run of each kind waits behind the one executing; the sandbox lock
  and the upload marker keep two runs off the same Orb.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [states: [:available, :scheduled], period: :infinity]

  alias Tuist.Sandboxes.Archives

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    # A failed upload is recorded on the Orb and retried later, like the
    # hourly run's.
    Archives.archive_oldest(account_id)
    :ok
  end

  def perform(_job) do
    Archives.run()
    :ok
  end
end
