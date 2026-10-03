defmodule Atlas.Product.Workers.IngestGitHubEvent do
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Product.GitHubIngestion

  @impl true
  def perform(%Oban.Job{args: %{"event_type" => event_type, "payload" => payload, "github_app_id" => github_app_id}}) do
    case GitHubIngestion.ingest(event_type, payload, github_app_id: github_app_id) do
      {:ok, _trace} -> :ok
      :ignored -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"event_type" => event_type, "payload" => payload}}) do
    case GitHubIngestion.ingest(event_type, payload) do
      {:ok, _trace} -> :ok
      :ignored -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
