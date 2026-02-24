defmodule Cache.BufferTestHelpers do
  @moduledoc """
  Shared setup helpers for starting test-local SQLiteBuffer instances
  and stubbing module-level buffer functions to use them.

  Each helper starts a supervised SQLiteBuffer with a unique name,
  allows the Ecto sandbox for its process, and stubs the buffer
  module's public functions to delegate to the test-local instance.

  The stubs call through to the real buffer functions (using the
  `name` parameter) so tests exercise the actual ETS insert logic
  rather than reimplementing it.
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1]
  import Mimic

  alias Cache.CacheArtifactsBuffer
  alias Cache.KeyValueBuffer
  alias Cache.S3TransfersBuffer
  alias Cache.SQLiteBuffer
  alias Ecto.Adapters.SQL.Sandbox

  @doc """
  Starts a test-local KeyValueBuffer and stubs module functions to use it.

  Adds `:kv_name` and `:unique_suffix` to the context.
  """
  def setup_key_value_buffer(context \\ %{}) do
    {suffix, context} = ensure_suffix(context)
    name = :"kv_buf_test_#{suffix}"
    pid = start_supervised!({SQLiteBuffer, [name: name, buffer_module: KeyValueBuffer]})
    Sandbox.allow(Cache.Repo, self(), pid)

    stub(KeyValueBuffer, :enqueue, fn key, payload ->
      KeyValueBuffer.enqueue(key, payload, name)
    end)

    stub(KeyValueBuffer, :enqueue_access, fn key ->
      KeyValueBuffer.enqueue_access(key, name)
    end)

    stub(KeyValueBuffer, :flush, fn -> SQLiteBuffer.flush(name) end)
    stub(KeyValueBuffer, :queue_stats, fn -> SQLiteBuffer.queue_stats(name) end)
    stub(KeyValueBuffer, :reset, fn -> SQLiteBuffer.reset(name) end)

    Map.put(context, :kv_name, name)
  end

  @doc """
  Starts a test-local CacheArtifactsBuffer and stubs module functions to use it.

  Adds `:ca_name` and `:unique_suffix` to the context.
  """
  def setup_cache_artifacts_buffer(context \\ %{}) do
    {suffix, context} = ensure_suffix(context)
    name = :"ca_buf_test_#{suffix}"
    pid = start_supervised!({SQLiteBuffer, [name: name, buffer_module: CacheArtifactsBuffer]})
    Sandbox.allow(Cache.Repo, self(), pid)

    stub(CacheArtifactsBuffer, :enqueue_access, fn key, size_bytes, last_accessed_at ->
      CacheArtifactsBuffer.enqueue_access(key, size_bytes, last_accessed_at, name)
    end)

    stub(CacheArtifactsBuffer, :enqueue_delete, fn key ->
      CacheArtifactsBuffer.enqueue_delete(key, name)
    end)

    stub(CacheArtifactsBuffer, :flush, fn -> SQLiteBuffer.flush(name) end)
    stub(CacheArtifactsBuffer, :queue_stats, fn -> SQLiteBuffer.queue_stats(name) end)
    stub(CacheArtifactsBuffer, :reset, fn -> SQLiteBuffer.reset(name) end)

    Map.put(context, :ca_name, name)
  end

  @doc """
  Starts a test-local S3TransfersBuffer and stubs module functions to use it.

  Adds `:s3_name` and `:unique_suffix` to the context.
  """
  def setup_s3_transfers_buffer(context \\ %{}) do
    {suffix, context} = ensure_suffix(context)
    name = :"s3_buf_test_#{suffix}"
    pid = start_supervised!({SQLiteBuffer, [name: name, buffer_module: S3TransfersBuffer]})
    Sandbox.allow(Cache.Repo, self(), pid)

    stub(S3TransfersBuffer, :enqueue, fn type, account_handle, project_handle, artifact_type, key ->
      S3TransfersBuffer.enqueue(type, account_handle, project_handle, artifact_type, key, name)
    end)

    stub(S3TransfersBuffer, :enqueue_delete, fn id ->
      S3TransfersBuffer.enqueue_delete(id, name)
    end)

    stub(S3TransfersBuffer, :flush, fn -> SQLiteBuffer.flush(name) end)
    stub(S3TransfersBuffer, :queue_stats, fn -> SQLiteBuffer.queue_stats(name) end)
    stub(S3TransfersBuffer, :reset, fn -> SQLiteBuffer.reset(name) end)

    Map.put(context, :s3_name, name)
  end

  defp ensure_suffix(%{unique_suffix: suffix} = context), do: {suffix, context}

  defp ensure_suffix(context) do
    suffix = :erlang.unique_integer([:positive])
    {suffix, Map.put(context, :unique_suffix, suffix)}
  end
end
