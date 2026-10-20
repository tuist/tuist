defmodule Tuist.Runners.Workers.GitLabPollWorker do
  @moduledoc "Bounded GitLab polling with scheduled pauses on a dedicated queue."
  use Oban.Worker,
    queue: :runner_gitlab,
    max_attempts: 1,
    unique: [period: 120, keys: [:connection_id], states: [:available, :scheduled, :executing]]

  alias Tuist.Runners.GitLab

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => id}} = job) do
    case GitLab.get_connection(id) do
      nil ->
        :ok

      connection ->
        result = GitLab.poll(connection)
        GitLab.record_poll_result(connection, result)

        if continue_polling?(result) and DateTime.diff(DateTime.utc_now(), job.inserted_at) < 50 do
          {:snooze, 5}
        else
          :ok
        end
    end
  end

  def perform(_job) do
    GitLab.purge_expired_payloads()

    Enum.each(GitLab.list_pollable_connections(), fn connection ->
      %{connection_id: connection.id} |> __MODULE__.new() |> Oban.insert()
    end)

    :ok
  end

  defp continue_polling?({:ok, :inactive}), do: false
  defp continue_polling?({:ok, _}), do: true
  defp continue_polling?({:error, :invalid_job_tags}), do: true
  defp continue_polling?(_), do: false
end
