defmodule Tuist.Repo.PoolMetrics do
  @moduledoc false

  @repos [
    {Tuist.Repo, "postgres", "postgres"},
    {Tuist.ClickHouseRepo, "clickhouse_read", "clickhouse"},
    {Tuist.IngestRepo, "clickhouse_write", "clickhouse"}
  ]

  def repos do
    Enum.map(@repos, &elem(&1, 0))
  end

  def running?(repo) do
    Enum.member?(Ecto.Repo.all_running(), repo)
  end

  def connection_pool_metrics(repo) do
    repo
    |> connection_pool_pid()
    |> DBConnection.ConnectionPool.get_connection_metrics()
    |> List.first()
    |> case do
      nil -> nil
      metrics -> Map.put(metrics, :pool_size, pool_size(repo))
    end
  end

  def telemetry_metadata(repo) do
    %{
      repo: repo_label(repo),
      database: database_label(repo)
    }
  end

  def repo_label(repo) do
    repo_metadata(repo, 1)
  end

  def database_label(repo) do
    repo_metadata(repo, 2)
  end

  def pool_size(repo) do
    Keyword.get(repo.config(), :pool_size)
  end

  defp repo_metadata(repo, index) do
    @repos
    |> Enum.find(fn {candidate, _, _} -> candidate == repo end)
    |> elem(index)
  end

  defp connection_pool_pid(repo) do
    repo
    |> :sys.get_state()
    |> elem(3)
    |> elem(1)
    |> Map.get(DBConnection.ConnectionPool)
    |> elem(1)
  end
end
