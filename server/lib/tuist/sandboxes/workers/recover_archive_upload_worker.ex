defmodule Tuist.Sandboxes.Workers.RecoverArchiveUploadWorker do
  @moduledoc """
  Reclaims uploads left by failed archive jobs. Scheduled atomically with
  the upload marker, so a database outage or a caller crash cannot lose
  the recovery. A live uploader holds a separate cluster-wide lock and is
  checked again a minute later; resume/delete never take that lock.
  """
  use Oban.Worker, queue: :default, max_attempts: 10

  alias Tuist.Sandboxes.Archives

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => id, "upload_id" => upload_id}}) do
    Archives.recover_upload(id, upload_id)
  end
end
