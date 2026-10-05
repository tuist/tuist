defmodule Tuist.MCP.Events.Workers.FanoutWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [keys: [:event_name, :project_id, :account_id, :source_id], states: :all, period: {31, :days}]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.DeliveryWorker
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    name = Map.get(args, "event_name", "test_case.marked_flaky")
    now = DateTime.utc_now()

    case target(args) do
      nil ->
        :ok

      {scope, data} ->
        scope
        |> subscriptions(name, now)
        |> Enum.reduce_while(:ok, fn subscription, _acc ->
          event_id =
            "evt_" <>
              Base.url_encode64(:crypto.hash(:sha256, "#{subscription.id}:#{args["source_id"]}"), padding: false)

          body = %{
            "eventId" => event_id,
            "name" => name,
            "timestamp" => DateTime.to_iso8601(now),
            "data" => event_data(name, args, data),
            "cursor" => nil
          }

          result =
            %{"subscription_id" => subscription.id, "event_id" => event_id, "body" => body}
            |> DeliveryWorker.new()
            |> Oban.insert()

          case result do
            {:ok, _job} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp target(%{"project_id" => project_id}) do
    case Repo.get(Project, project_id) do
      nil -> nil
      project -> {{:project, project.id}, {Repo.preload(project, :account).account.name, project.name}}
    end
  end

  defp target(%{"account_id" => account_id}) do
    case Repo.get(Account, account_id) do
      nil -> nil
      account -> {{:account, account.id}, account.name}
    end
  end

  defp subscriptions({:project, project_id}, name, now) do
    Repo.all(
      from s in Subscription,
        where: s.project_id == ^project_id and s.event_name == ^name and s.refresh_before > ^now
    )
  end

  defp subscriptions({:account, account_id}, name, now) do
    Repo.all(
      from s in Subscription,
        where:
          s.account_id == ^account_id and is_nil(s.project_id) and s.event_name == ^name and
            s.refresh_before > ^now
    )
  end

  defp event_data("test_case.marked_flaky", %{"test_case_id" => id}, {account, project}) do
    project_data(account, project, %{"test_case_id" => id}, "tests/test-cases/#{id}")
  end

  defp event_data("build.failed", %{"build_id" => id, "build_system" => system}, {account, project}) do
    path = if system == "bazel", do: "builds/invocations/#{id}", else: "builds/build-runs/#{id}"
    project_data(account, project, %{"build_id" => id, "build_system" => system}, path)
  end

  defp event_data("test_run.failed", %{"test_run_id" => id}, {account, project}) do
    project_data(account, project, %{"test_run_id" => id}, "tests/test-runs/#{id}")
  end

  defp event_data("ci_job.failed", %{"workflow_job_id" => id, "workflow_run_id" => run_id}, account) do
    %{
      "account_handle" => account,
      "workflow_job_id" => id,
      "workflow_run_id" => run_id,
      "url" => "#{Tuist.Environment.app_url()}/#{account}/runners/runs/#{run_id}/jobs/#{id}"
    }
  end

  defp project_data(account, project, fields, path) do
    Map.merge(fields, %{
      "account_handle" => account,
      "project_handle" => project,
      "url" => "#{Tuist.Environment.app_url()}/#{account}/#{project}/#{path}"
    })
  end
end
