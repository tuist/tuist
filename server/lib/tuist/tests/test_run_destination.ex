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
  Normalises the xcresult `platform` string into the atom convention used by
  `TuistWeb.Previews.PlatformIcon.platform_icon_name/1` (e.g. "iOS Simulator"
  becomes `:ios_simulator`, "macOS" becomes `:macos`). `iPadOS` variants are
  mapped onto the iOS family since the icon set has no separate iPad glyph.
  Returns `:unknown` for unrecognised or missing platforms.
  """
  def platform_atom(%__MODULE__{platform: platform}), do: platform_atom(platform)
  def platform_atom("macOS"), do: :macos
  def platform_atom("iOS"), do: :ios
  def platform_atom("iOS Simulator"), do: :ios_simulator
  def platform_atom("iPadOS"), do: :ios
  def platform_atom("iPadOS Simulator"), do: :ios_simulator
  def platform_atom("tvOS"), do: :tvos
  def platform_atom("tvOS Simulator"), do: :tvos_simulator
  def platform_atom("watchOS"), do: :watchos
  def platform_atom("watchOS Simulator"), do: :watchos_simulator
  def platform_atom("visionOS"), do: :visionos
  def platform_atom("visionOS Simulator"), do: :visionos_simulator
  def platform_atom(_), do: :unknown
end
