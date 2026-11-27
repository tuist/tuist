defmodule TuistOps.Paging.Workers.PageWorker do
  @moduledoc """
  Runs `TuistOps.Paging.handle_mention/2` off the request, because
  Slack retries an event that is not acknowledged within three seconds.
  Unique on the Slack `event_id`, so those retries never page twice.
  A failed page retries; the last attempt tells the channel it failed.
  """

  use Oban.Worker,
    queue: :paging,
    max_attempts: 3,
    unique: [period: 3600, fields: [:args], keys: [:event_id]]

  alias TuistOps.Paging

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event}, attempt: attempt, max_attempts: max_attempts}) do
    Paging.handle_mention(event, attempt >= max_attempts)
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 10
end
