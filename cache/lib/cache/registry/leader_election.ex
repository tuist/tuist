defmodule Cache.Registry.LeaderElection do
  @moduledoc """
  Leader election for registry sync using S3 conditional writes.

  Only one cache node should sync packages from GitHub to respect rate limits.
  This module implements leader election using S3 as a distributed lock store.

  ## Lock File

  The lock is stored at `registry/sync/leader.lock` in S3 with the following JSON content:

  ```json
  {
    "node": "<hostname>",
    "acquired_at": "<iso8601>",
    "expires_at": "<iso8601>"
  }
  ```

  ## Algorithm

  1. Try conditional PUT with `if_none_match: "*"` (only succeeds if no lock exists)
  2. If 412 (conflict): read existing lock
  3. If expired: delete lock, retry conditional PUT
  4. Return `{:ok, :acquired}` or `{:error, :already_locked}`

  ## TTL

  Locks expire after 70 minutes (4200 seconds). This allows for long sync operations
  while ensuring recovery if a node crashes.

  ## Consistency

  All operations use the `x-tigris-consistent: true` header to ensure strong
  consistency across S3 operations.
  """

  require Logger

  @lock_key "registry/sync/leader.lock"
  @ttl_seconds 4200

  @doc """
  Attempt to become the leader by acquiring the lock.

  Returns:
  - `{:ok, :acquired}` - Successfully acquired the lock
  - `{:error, :already_locked}` - Another node holds a valid lock
  """
  @spec try_acquire_lock() :: {:ok, :acquired} | {:error, :already_locked}
  def try_acquire_lock do
    node_name = get_node_name()
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, @ttl_seconds, :second)

    lock_content =
      Jason.encode!(%{
        "node" => node_name,
        "acquired_at" => DateTime.to_iso8601(now),
        "expires_at" => DateTime.to_iso8601(expires_at)
      })

    case try_conditional_put(lock_content) do
      {:ok, :acquired} ->
        Logger.info("Leader lock acquired by #{node_name}")
        {:ok, :acquired}

      {:error, :conflict} ->
        handle_conflict(lock_content)
    end
  end

  @doc """
  Release the lock (only if we're the leader).

  Returns:
  - `:ok` - Lock released successfully
  - `{:error, :not_leader}` - We don't hold the lock
  """
  @spec release_lock() :: :ok | {:error, :not_leader}
  def release_lock do
    node_name = get_node_name()

    case current_leader() do
      {:ok, ^node_name} ->
        delete_lock()
        Logger.info("Leader lock released by #{node_name}")
        :ok

      {:ok, _other_node} ->
        {:error, :not_leader}

      {:error, :no_lock} ->
        {:error, :not_leader}
    end
  end

  @doc """
  Check if the current node holds a valid (non-expired) lock.

  Returns `true` if this node is the leader with a valid lock, `false` otherwise.
  """
  @spec is_leader?() :: boolean()
  def is_leader? do
    case current_leader() do
      {:ok, leader_node} ->
        leader_node == get_node_name()

      {:error, :no_lock} ->
        false
    end
  end

  @doc """
  Read the lock file and return the leader node name.

  Returns:
  - `{:ok, node_name}` - The node holding a valid lock
  - `{:error, :no_lock}` - No lock exists or lock is expired
  """
  @spec current_leader() :: {:ok, String.t()} | {:error, :no_lock}
  def current_leader do
    bucket = get_bucket()

    operation =
      bucket
      |> ExAws.S3.get_object(@lock_key)
      |> with_tigris_consistent()

    case ExAws.request(operation) do
      {:ok, %{body: body}} ->
        parse_and_validate_lock(body)

      {:error, {:http_error, 404, _}} ->
        {:error, :no_lock}

      {:error, reason} ->
        Logger.warning("Failed to read leader lock: #{inspect(reason)}")
        {:error, :no_lock}
    end
  end

  defp try_conditional_put(lock_content) do
    bucket = get_bucket()

    operation =
      bucket
      |> ExAws.S3.put_object(@lock_key, lock_content,
        content_type: "application/json",
        if_none_match: "*"
      )
      |> with_tigris_consistent()

    case ExAws.request(operation) do
      {:ok, _} ->
        {:ok, :acquired}

      {:error, {:http_error, 412, _}} ->
        {:error, :conflict}

      {:error, reason} ->
        Logger.error("Failed to acquire leader lock: #{inspect(reason)}")
        {:error, :conflict}
    end
  end

  defp handle_conflict(lock_content) do
    case current_leader() do
      {:ok, _leader_node} ->
        {:error, :already_locked}

      {:error, :no_lock} ->
        delete_lock()

        case try_conditional_put(lock_content) do
          {:ok, :acquired} ->
            Logger.info("Leader lock acquired after expired lock cleanup")
            {:ok, :acquired}

          {:error, :conflict} ->
            {:error, :already_locked}
        end
    end
  end

  defp parse_and_validate_lock(body) do
    case Jason.decode(body) do
      {:ok, %{"node" => node, "expires_at" => expires_at_str}} ->
        case DateTime.from_iso8601(expires_at_str) do
          {:ok, expires_at, _offset} ->
            if DateTime.before?(DateTime.utc_now(), expires_at) do
              {:ok, node}
            else
              {:error, :no_lock}
            end

          {:error, _} ->
            {:error, :no_lock}
        end

      _ ->
        {:error, :no_lock}
    end
  end

  defp delete_lock do
    bucket = get_bucket()

    operation =
      bucket
      |> ExAws.S3.delete_object(@lock_key)
      |> with_tigris_consistent()

    case ExAws.request(operation) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to delete leader lock: #{inspect(reason)}")
        :ok
    end
  end

  defp with_tigris_consistent(operation) do
    %{operation | headers: Map.put(operation.headers, "x-tigris-consistent", "true")}
  end

  defp get_bucket do
    Application.get_env(:cache, :s3)[:bucket]
  end

  defp get_node_name do
    System.get_env("PHX_HOST") || System.get_env("HOSTNAME") || "unknown"
  end
end
