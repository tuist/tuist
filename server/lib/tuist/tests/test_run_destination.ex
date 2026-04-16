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
  Normalises a raw xcresult `platform` value (e.g. "iOS Simulator", "macOS")
  into the snake-case form stored in `test_run_destinations.platform`. The
  stored form mirrors the atom convention used elsewhere in the codebase
  (preview platforms etc.), but as a string — ClickHouse is the source of
  truth for these values, and we don't round-trip them through atoms.

  `iPadOS` variants fold onto the iOS family since the icon set has no
  separate iPad glyph. Returns `"unknown"` for unrecognised or missing input.
  """
  def normalize_platform("macOS"), do: "macos"
  def normalize_platform("iOS"), do: "ios"
  def normalize_platform("iOS Simulator"), do: "ios_simulator"
  def normalize_platform("iPadOS"), do: "ios"
  def normalize_platform("iPadOS Simulator"), do: "ios_simulator"
  def normalize_platform("tvOS"), do: "tvos"
  def normalize_platform("tvOS Simulator"), do: "tvos_simulator"
  def normalize_platform("watchOS"), do: "watchos"
  def normalize_platform("watchOS Simulator"), do: "watchos_simulator"
  def normalize_platform("visionOS"), do: "visionos"
  def normalize_platform("visionOS Simulator"), do: "visionos_simulator"
  def normalize_platform(_), do: "unknown"

  @doc """
  Reverses `normalize_platform/1` for display (e.g. "watchos_simulator" →
  "watchOS Simulator"). Falls back to the raw value when the stored string
  isn't a recognised platform.
  """
  def humanize_platform(%__MODULE__{platform: platform}), do: humanize_platform(platform)
  def humanize_platform("macos"), do: "macOS"
  def humanize_platform("ios"), do: "iOS"
  def humanize_platform("ios_simulator"), do: "iOS Simulator"
  def humanize_platform("tvos"), do: "tvOS"
  def humanize_platform("tvos_simulator"), do: "tvOS Simulator"
  def humanize_platform("watchos"), do: "watchOS"
  def humanize_platform("watchos_simulator"), do: "watchOS Simulator"
  def humanize_platform("visionos"), do: "visionOS"
  def humanize_platform("visionos_simulator"), do: "visionOS Simulator"
  def humanize_platform(other) when is_binary(other), do: other
  def humanize_platform(_), do: ""
end
