defmodule Tuist.Cache do
  @moduledoc """
  The cache context.
  """

  import Ecto.Query

  alias Tuist.Cache.Entry
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
      id: Ecto.UUID.generate(),
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
    IngestRepo.all(from(e in Entry, where: e.cas_id == ^cas_id and e.project_id == ^project_id))
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
end
