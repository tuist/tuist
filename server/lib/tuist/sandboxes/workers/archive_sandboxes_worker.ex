defmodule Tuist.Sandboxes.Workers.ArchiveSandboxesWorker do
  @moduledoc """
  Moves Amp Orbs paused longer than the archive threshold, or past their
  account's newest ten paused on nodes, off their nodes into object storage, and cleans up
  archives of restored Orbs and uploads or restores whose caller died
  (`Tuist.Sandboxes.Archives.run/0`). A job with an `account_id` instead
  archives that account's least recently paused idle Orb to make room under
  its disk limit (`Archives.make_room/1`), and one with a `sandbox_id`
  archives that sandbox, which someone asked for (`Archives.request/1`). An
  archive can take minutes, so at
  most one run of each kind waits behind the one executing; the sandbox lock
  and the upload marker keep two runs off the same Orb.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [states: [:available, :scheduled], period: :infinity]

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Sandbox

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id}}) do
    # A sandbox resumed meanwhile is skipped by `archive/1`, a deleted one never loads.
    with %Sandbox{} = sandbox <- Sandboxes.get_sandbox_by_id(sandbox_id) do
      Archives.archive(sandbox)
    end

    :ok
  end

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
