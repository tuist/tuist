defmodule Tuist.MCP.Events.Publisher do
  @moduledoc false

  import Ecto.Query

  alias Tuist.MCP.Events.Catalog
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
      Enum.each(entries, fn {data, source_id} -> enqueue(name, data, source_id) end)
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

    case Oban.insert(FanoutWorker.new(args)) do
      {:ok, _job} -> :ok
      {:error, reason} -> Logger.warning("MCP event fan-out could not be queued: #{inspect(reason)}")
    end
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
