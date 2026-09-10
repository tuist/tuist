defmodule Tuist.Runners.Workers.GitLabPollWorker do
  @moduledoc "One bounded GitLab long-poll per connection; the cron fans out independently."
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: :infinity, keys: [:connection_id], states: [:available, :scheduled, :executing]]

  alias Tuist.Runners.GitLab

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => id}}) do
    case GitLab.get_connection(id) do
      nil ->
        :ok

      connection ->
        poll_window(connection, System.monotonic_time(:millisecond) + 55_000)
    end
  end

  def perform(_job) do
    GitLab.purge_expired_payloads()

    Enum.each(GitLab.list_pollable_connections(), fn connection ->
      %{connection_id: connection.id} |> __MODULE__.new() |> Oban.insert()
    end)

    :ok
  end

  defp poll_window(connection, deadline) do
    result = GitLab.poll(connection)
    GitLab.record_poll_result(connection, result)

    if match?({:ok, _}, result) and System.monotonic_time(:millisecond) + 5_000 < deadline do
      Process.sleep(5_000)
      poll_window(connection, deadline)
    else
      :ok
    end
  end
end
