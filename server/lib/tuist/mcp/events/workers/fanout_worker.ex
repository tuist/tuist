defmodule Tuist.MCP.Events.Workers.FanoutWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :mcp_events,
    max_attempts: 5

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.MCP.Events.Payload
  alias Tuist.MCP.Events.Queue
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.DeliveryWorker
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(second: 30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    name = Map.get(args, "event_name", "test_case.marked_flaky")
    now = DateTime.utc_now()

    case target(args) do
      nil ->
        :ok

      {scope, data} ->
        enqueue_subscriptions(scope, name, args["source_id"], Payload.data(name, args, data), now, nil)
    end
  end

  defp enqueue_subscriptions(scope, name, source_id, data, now, cursor) do
    query = subscriptions(scope, name, now)
    query = if cursor, do: where(query, [s], s.id > ^cursor), else: query

    ids = Repo.all(from s in query, order_by: [asc: s.id], limit: 100, select: s.id)

    case ids do
      [] ->
        :ok

      _ ->
        jobs =
          Enum.map(ids, fn id ->
            event_id = "evt_" <> Base.url_encode64(:crypto.hash(:sha256, "#{id}:#{source_id}"), padding: false)

            body = %{
              "eventId" => event_id,
              "name" => name,
              "timestamp" => DateTime.to_iso8601(now),
              "data" => data,
              "cursor" => nil
            }

            key = Queue.key(["delivery", id, event_id])
            {key, DeliveryWorker.new(%{"subscription_id" => id, "event_id" => event_id, "body" => body})}
          end)

        case Queue.enqueue(jobs) do
          :ok ->
            if length(ids) == 100,
              do: enqueue_subscriptions(scope, name, source_id, data, now, List.last(ids)),
              else: :ok

          {:error, reason} ->
            {:error, reason}
        end
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
    from s in Subscription,
      where: s.project_id == ^project_id and s.event_name == ^name and s.refresh_before > ^now
  end

  defp subscriptions({:account, account_id}, name, now) do
    from s in Subscription,
      where:
        s.account_id == ^account_id and is_nil(s.project_id) and s.event_name == ^name and
          s.refresh_before > ^now
  end
end
