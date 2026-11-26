defmodule Atlas.GTM.Workers.PublishSocialPost do
  @moduledoc """
  Publishes one approved revision of a publication at its scheduled time.
  Runs once: a publish that may have reached X is never retried, and an edit
  or cancellation after approval turns the job into a no-op.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.GTM.SocialPublishing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"publication_id" => id, "revision" => revision}}) do
    case SocialPublishing.publish(id, revision) do
      {:error, publication} -> {:cancel, publication.last_error}
      _published_or_skipped -> :ok
    end
  end
end
