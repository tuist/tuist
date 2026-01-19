defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  import Ecto.Query

  alias Tuist.Cache.CASEvent
  alias Tuist.Cache.Entry
  alias Tuist.Cache.ModuleCacheEvent
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo

  @doc """
  Creates a cache entry.

  ## Examples

      iex> create_entry(%{cas_id: "some_id", key: "some_key", value: "some_value", project_id: 123})
      {:ok, %Entry{}}

      iex> create_entry(%{})
      {:error, %Ecto.Changeset{}}

  """
  def create_entry(attrs \\ %{}) do
    entry_attrs = %{
      id: UUIDv7.generate(),
      cas_id: attrs[:cas_id],
      value: attrs[:value],
      project_id: attrs[:project_id],
      inserted_at: attrs[:inserted_at] || NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }

    entry = struct(Entry, entry_attrs)

    IngestRepo.insert(entry)
  end

  @doc """
  Gets all cache entries by cas_id and project_id.

  ## Examples

      iex> get_entries_by_cas_id_and_project_id("some_cas_id", 123)
      [%Entry{}, ...]

  """
  def get_entries_by_cas_id_and_project_id(cas_id, project_id) do
    ClickHouseRepo.all(from(e in Entry, where: e.cas_id == ^cas_id and e.project_id == ^project_id))
  end

  @doc """
  Deletes all cache entries for a given project.

  ## Examples

      iex> delete_entries_by_project_id(123)
      {:ok, 5}

  """
  def delete_entries_by_project_id(project_id) do
    IngestRepo.delete_all(from(e in Entry, where: e.project_id == ^project_id))
  end

  @doc """
  Creates multiple CAS analytics events in a batch.

  ## Examples

      iex> create_cas_events([%{action: "upload", size: 1024, cas_id: "abc123", project_id: 1}, ...])
      {:ok, 2}
  """
  def create_cas_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          action: event.action,
          size: event.size,
          cas_id: event.cas_id,
          project_id: event.project_id,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(CASEvent, entries)
  end

  @doc """
  Creates multiple module cache events in a batch.

  ## Examples

      iex> create_module_cache_events([%{project_id: 1, run_id: "run", source: "disk"}, ...])
      {:ok, 2}
  """
  def create_module_cache_events(events) when is_list(events) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(events, fn event ->
        %{
          id: UUIDv7.generate(),
          project_id: event.project_id,
          run_id: event.run_id,
          source: event.source,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(ModuleCacheEvent, entries)
  end

  def count_module_cache_hit_runs([], _start_datetime, _end_datetime), do: 0

  def count_module_cache_hit_runs(project_ids, start_datetime, end_datetime) do
    query =
      from(e in ModuleCacheEvent,
        where: e.project_id in ^project_ids,
        where: e.inserted_at >= ^DateTime.to_naive(start_datetime),
        where: e.inserted_at <= ^DateTime.to_naive(end_datetime),
        select: fragment("count(DISTINCT (toString(?), ?))", e.project_id, e.run_id)
      )

    ClickHouseRepo.one(query) || 0
  end
end
