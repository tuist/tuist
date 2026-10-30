defmodule Tuist.Runners.CacheVolumes.SavedSize do
  @moduledoc false
  use Ecto.Schema

  schema "runner_cache_volume_saved_sizes" do
    belongs_to(:volume, Tuist.Runners.CacheVolumes.Volume, type: :binary_id)
    field(:size_bytes, :integer)
    field(:observed_at, :utc_datetime_usec)
  end
end
