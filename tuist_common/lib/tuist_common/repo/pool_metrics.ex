defmodule TuistCommon.Repo.PoolMetrics do
  @moduledoc false

  def running?(repo) do
    Enum.member?(apply(Ecto.Repo, :all_running, []), repo)
  end

  def connection_pool_metrics(repo) do
    case connection_pool_pid(repo) do
      nil ->
        nil

      pool_pid ->
        pool_pid
        |> then(&apply(DBConnection.ConnectionPool, :get_connection_metrics, [&1]))
        |> List.first()
        |> case do
          nil -> nil
          metrics -> Map.put(metrics, :pool_size, pool_size(repo))
        end
    end
  end

  defp pool_size(repo) do
    repo.config()
    |> Keyword.get(:pool_size)
  end

  defp connection_pool_pid(repo) do
    # DBConnection does not register the pool under a stable name, so we
    # introspect the repo supervisor state and extract the pool child pid.
    case :sys.get_state(repo) do
      {_, _, _, {_, children}, _, _, _, _, _, _, _} when is_map(children) ->
        case Map.get(children, DBConnection.ConnectionPool) do
          {_, pool_pid, _, _, _, _, _} -> pool_pid
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
