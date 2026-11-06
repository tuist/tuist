defmodule Tuist.MCP.Events.Publisher do
  @moduledoc false

  import Ecto.Query

  alias Tuist.MCP.Events.Catalog
  alias Tuist.MCP.Events.Queue
  alias Tuist.MCP.Events.Subscription
  alias Tuist.MCP.Events.Workers.FanoutWorker
  alias Tuist.Repo

  require Logger

  def publish(name, data, source_id) do
    if Catalog.supported?(name) do
      publish_supported(name, data, source_id)
    else
      {:error, :unsupported_event}
    end
  end

  def publish_batch(_name, [], _target), do: :ok

  def publish_batch(name, entries, target) when is_list(entries) and is_map(target) do
    if Catalog.supported?(name) and active_subscriptions?(name, target) do
      jobs =
        Enum.map(entries, fn {data, source_id} ->
          args = data |> Map.put("event_name", name) |> Map.put("source_id", to_string(source_id))
          {Queue.key(["fanout", name, target, to_string(source_id)]), FanoutWorker.new(args)}
        end)

      log_enqueue_result(Queue.enqueue(jobs))
    end

    :ok
  end

  defp publish_supported(name, data, source_id) do
    if active_subscriptions?(name, data) do
      enqueue(name, data, source_id)
    else
      :ok
    end
  end

  defp enqueue(name, data, source_id) do
    args = data |> Map.put("event_name", name) |> Map.put("source_id", to_string(source_id))
    key = Queue.key(["fanout", name, Map.take(data, ["project_id", "account_id"]), to_string(source_id)])
    [{key, FanoutWorker.new(args)}] |> Queue.enqueue() |> log_enqueue_result()
  end

  defp log_enqueue_result(:ok), do: :ok

  defp log_enqueue_result({:error, reason}) do
    Logger.warning("MCP event fan-out could not be queued: #{inspect(reason)}")
    :ok
  end

  defp active_subscriptions?(name, data) do
    now = DateTime.utc_now()
    query = from s in Subscription, where: s.event_name == ^name and s.refresh_before > ^now

    query =
      if project_id = data["project_id"] do
        where(query, [s], s.project_id == ^project_id)
      else
        account_id = data["account_id"]
        where(query, [s], s.account_id == ^account_id and is_nil(s.project_id))
      end

    Repo.exists?(query)
  end
end
