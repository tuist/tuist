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
    repo
    |> :sys.get_state()
    |> children_from_repo_state()
    |> case do
      children when is_map(children) ->
        case Map.get(children, DBConnection.ConnectionPool) do
          child when is_tuple(child) and tuple_size(child) >= 2 -> elem(child, 1)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp children_from_repo_state(repo_state)
       when is_tuple(repo_state) and tuple_size(repo_state) >= 4 do
    case elem(repo_state, 3) do
      {_, children} when is_map(children) -> children
      _ -> nil
    end
  end

  defp children_from_repo_state(_), do: nil
end
