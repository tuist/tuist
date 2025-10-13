defmodule Tuist.CAS do
  @moduledoc """
  The CAS context.
  """

  alias Tuist.CAS.Entry
  alias Tuist.IngestRepo

  @doc """
  Creates a CAS entry.

  ## Examples

      iex> create_entry(%{cas_id: "some_id", key: "some_key", value: "some_value", project_id: 123})
      {:ok, %Entry{}}

      iex> create_entry(%{})
      {:error, %Ecto.Changeset{}}

  """
  def create_entry(attrs \\ %{}) do
    entry_attrs = %{
      id: Ecto.UUID.generate(),
      cas_id: attrs.cas_id,
      value: attrs.value,
      project_id: attrs.project_id,
      inserted_at: attrs[:inserted_at] || NaiveDateTime.utc_now()
    }

    entry = struct(Entry, entry_attrs)

    case IngestRepo.insert(entry) do
      {:ok, entry} -> {:ok, entry}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets all CAS entries by cas_id.

  ## Examples

      iex> get_entries_by_cas_id("some_cas_id")
      [%Entry{}, ...]

  """
  def get_entries_by_cas_id(cas_id) do
    import Ecto.Query

    from(e in Entry, where: e.cas_id == ^cas_id)
    |> IngestRepo.all()
  end
end
