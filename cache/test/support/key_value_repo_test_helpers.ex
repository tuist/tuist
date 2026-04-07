defmodule Cache.KeyValueRepoTestHelpers do
  @moduledoc false

  alias Cache.DistributedKV.State
  alias Cache.KeyValueEntry
  alias Cache.KeyValueWriteRepo

  def reset! do
    KeyValueWriteRepo.delete_all(State)
    KeyValueWriteRepo.delete_all(KeyValueEntry)
    :ok
  end
end
