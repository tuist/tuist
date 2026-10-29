defmodule Tuist.Runners.CacheVolumes.Measurement do
  @moduledoc false
  use Ecto.Schema

  schema "runner_cache_volume_measurements" do
    belongs_to(:usage, Tuist.Runners.CacheVolumes.Usage, type: :binary_id)
    field(:size_bytes, :integer)
    field(:capacity_bytes, :integer)
    field(:deleted, :boolean, default: false)
    field(:observed_at, :utc_datetime_usec)
  end
end
