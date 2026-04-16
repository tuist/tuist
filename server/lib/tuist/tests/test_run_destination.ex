defmodule Tuist.Tests.TestRunDestination do
  @moduledoc """
  A run destination records one device/simulator a test run executed on
  (for example `iPad (A16)` on `iOS Simulator 26.4`). Stored in ClickHouse
  and associated to a `Tuist.Tests.Test` via `test_run_id`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_run_destinations" do
    field :test_run_id, Ecto.UUID
    field :name, Ch, type: "String"
    field :platform, Ch, type: "LowCardinality(String)"
    field :os_version, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end

  def create_changeset(destination, attrs) do
    destination
    |> cast(attrs, [:id, :test_run_id, :name, :platform, :os_version, :inserted_at])
    |> validate_required([:id, :test_run_id, :name, :platform, :os_version])
  end

  @doc """
  Maps an xcresult platform string (e.g. "iOS Simulator", "macOS") to the
  corresponding Noora icon name. Falls back to a generic device icon when the
  platform is unrecognised.
  """
  def icon_name(%__MODULE__{platform: platform}), do: icon_name(platform)
  def icon_name("macOS"), do: "device_laptop"
  def icon_name("iOS"), do: "device_mobile"
  def icon_name("iOS Simulator"), do: "device_mobile_share"
  def icon_name("iPadOS"), do: "device_mobile"
  def icon_name("iPadOS Simulator"), do: "device_mobile_share"
  def icon_name("tvOS"), do: "device_desktop"
  def icon_name("tvOS Simulator"), do: "device_desktop_share"
  def icon_name("watchOS"), do: "device_watch"
  def icon_name("watchOS Simulator"), do: "device_watch_share"
  def icon_name("visionOS"), do: "device_vision_pro"
  def icon_name("visionOS Simulator"), do: "device_vision_pro_share"
  def icon_name(_), do: "devices"
end
