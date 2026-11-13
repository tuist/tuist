defmodule Tuist.Sandboxes.Workers.ArchiveSandboxesWorker do
  @moduledoc """
  Moves Amp Orbs paused longer than the archive threshold off their nodes
  into object storage, and cleans up
  archives of restored Orbs and uploads or restores whose caller died
  (`Tuist.Sandboxes.Archives.run/0`). A job with `node_names` instead
  archives the least
  recently paused idle Orb on those nodes, whose disk refused a new
  sandbox (`Archives.make_node_room/1`) or exceeded the high-water mark
  (`disk_pressure: true`, rechecked before uploading), and one with a `sandbox_id`
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

  def perform(%Oban.Job{args: %{"node_names" => node_names} = args}) do
    Archives.archive_oldest_on(node_names, disk_pressure: args["disk_pressure"] == true)
    :ok
  end

  def perform(_job) do
    Archives.run()
    :ok
  end
end
