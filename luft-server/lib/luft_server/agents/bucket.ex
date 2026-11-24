defmodule LuftServer.Agents.Bucket do
  @moduledoc """
  Strongly consistent PostgreSQL object bucket for Condukt session journals.
  Bodies are opaque; encryption belongs to `LuftServer.Agents.SessionStore`.
  """
  @behaviour Condukt.SessionStore.ObjectStore.Bucket

  alias LuftServer.Repo

  @impl true
  def create(_config, key, body) do
    case Repo.query(
           "INSERT INTO agent_objects (key, body) VALUES ($1, $2) ON CONFLICT (key) DO NOTHING",
           [key, body],
           log: false
         ) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, %{num_rows: 0}} -> {:error, :exists}
      {:error, _} -> {:error, :database_unavailable}
    end
  end

  @impl true
  def get(_config, key) do
    case Repo.query("SELECT body FROM agent_objects WHERE key = $1", [key], log: false) do
      {:ok, %{rows: [[body]]}} -> {:ok, body}
      {:ok, %{rows: []}} -> :not_found
      {:error, _} -> {:error, :database_unavailable}
    end
  end

  @impl true
  def list(_config, prefix, start_after) do
    # Literal prefix comparison, not LIKE: session keys may contain % or _.
    case Repo.query(
           """
           SELECT key FROM agent_objects
           WHERE left(key, char_length($1)) = $1
             AND ($2::text IS NULL OR key COLLATE "C" > $2 COLLATE "C")
           ORDER BY key COLLATE "C"
           """,
           [prefix, start_after],
           log: false
         ) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, _} -> {:error, :database_unavailable}
    end
  end

  @impl true
  def delete(_config, key) do
    case Repo.query("DELETE FROM agent_objects WHERE key = $1", [key], log: false) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :database_unavailable}
    end
  end
end
