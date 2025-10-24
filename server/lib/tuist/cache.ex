defmodule Tuist.Cache do
  @moduledoc """
  The cache context using in-memory storage via Cachex.
  """

  alias Tuist.Cache.KeyValueStore

  @doc """
  Stores a list of values for a given key (cas_id and project_id).
  This overwrites any existing values.
  
  ## Examples

      iex> put_key_value("some_cas_id", 123, ["value1", "value2"])
      :ok

  """
  def put_key_value(cas_id, project_id, values) when is_list(values) do
    KeyValueStore.put_key_value(cas_id, project_id, values)
  end

  @doc """
  Gets all values for a given key (cas_id and project_id).

  ## Examples

      iex> get_key_value("some_cas_id", 123)
      ["value1", "value2"]

  """
  def get_key_value(cas_id, project_id) do
    KeyValueStore.get_key_value(cas_id, project_id)
  end
end
