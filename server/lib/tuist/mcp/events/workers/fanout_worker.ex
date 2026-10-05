defmodule Tuist.MCP.Events.Workers.FanoutWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [keys: [:project_id, :source_id], states: :all, period: {31, :days}]

  import Ecto.Query

  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.DeliveryWorker
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "test_case_id" => test_case_id, "source_id" => source_id}}) do
    case Repo.get(Project, project_id) do
      nil ->
        :ok

      project ->
        project = Repo.preload(project, :account)
        now = DateTime.utc_now()

        subscriptions =
          Repo.all(
            from s in Subscription,
              where:
                s.project_id == ^project_id and s.event_name == "test_case.marked_flaky" and
                  s.refresh_before > ^now
          )

        Enum.reduce_while(subscriptions, :ok, fn subscription, _acc ->
          event_id =
            "evt_" <> Base.url_encode64(:crypto.hash(:sha256, "#{subscription.id}:#{source_id}"), padding: false)

          data = %{
            "account_handle" => project.account.name,
            "project_handle" => project.name,
            "test_case_id" => test_case_id,
            "url" =>
              "#{Tuist.Environment.app_url()}/#{project.account.name}/#{project.name}/tests/test-cases/#{test_case_id}"
          }

          body = %{
            "eventId" => event_id,
            "name" => "test_case.marked_flaky",
            "timestamp" => DateTime.to_iso8601(now),
            "data" => data,
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
end
