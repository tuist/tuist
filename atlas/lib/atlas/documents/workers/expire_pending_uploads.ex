defmodule Atlas.Documents.Workers.ExpirePendingUploads do
  @moduledoc """
  Sweeps expired `pending_upload` document rows every 15 minutes. A row expires
  when its `upload_expires_at` passes without the client calling
  `finalize_document_upload`. The reserved object is best-effort deleted
  alongside the row so nothing lingers in storage.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Documents

  @impl true
  def perform(_job) do
    _swept = Documents.delete_expired_pending_uploads()
    :ok
  end
end
