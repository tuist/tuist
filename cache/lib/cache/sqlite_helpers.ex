defmodule Cache.SQLiteHelpers do
  @moduledoc false

  alias Cache.Config

  require Logger

  def busy_error?(%Exqlite.Error{message: message}) when is_binary(message) do
    String.contains?(message, ["database is locked", "Database busy", "SQLITE_BUSY"])
  end

  def busy_error?(_), do: false

  def contention_error?(error) do
    busy_error?(error) or match?(%DBConnection.ConnectionError{}, error)
  end

  def db_path(repo, fallback \\ "key_value.sqlite") do
    Application.get_env(:cache, repo)[:database] || fallback
  end

  def file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end

  def remaining_time(deadline_ms) do
    max(deadline_ms - System.monotonic_time(:millisecond), 0)
  end

  def restore_busy_timeout(repo) do
    set_busy_timeout!(repo, Config.repo_busy_timeout_ms(repo))
  rescue
    error ->
      if contention_error?(error) do
        :ok
      else
        Logger.warning("Failed to restore busy timeout for #{inspect(repo)}: #{inspect(error)}")
        :ok
      end
  end

  def set_busy_timeout!(repo, timeout_ms) do
    case repo.query("PRAGMA busy_timeout = #{max(timeout_ms, 0)}") do
      {:ok, _result} -> :ok
      {:error, error} -> raise error
    end
  end

  def query!(repo, query) do
    case repo.query(query) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def wal_file_size(path), do: file_size("#{path}-wal")

  def with_repo_busy_timeout(repo, timeout_ms, fun) when is_function(fun, 0) do
    default_timeout_ms = Config.repo_busy_timeout_ms(repo)

    repo.checkout(fn ->
      if timeout_ms == default_timeout_ms do
        fun.()
      else
        set_busy_timeout!(repo, timeout_ms)

        try do
          fun.()
        after
          restore_busy_timeout(repo)
        end
      end
    end)
  end
end
