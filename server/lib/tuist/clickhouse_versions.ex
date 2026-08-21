defmodule Tuist.ClickHouseVersions do
  @moduledoc """
  Canonical facts about ClickHouse version support, shared by the migration
  guard (`Tuist.ClickHouseCapabilities`), the docs self-hosting requirements,
  and the CI job that runs the suite against the oldest supported release.

  This is a dependency-free leaf module on purpose, like `Tuist.CLIVersions`:
  the docs loader expands it at compile time, and the CI job reads the release
  straight out of this file.
  """

  @minimum_supported_version "25"
  @oldest_tested_release "25.8.31.9-lts"

  @doc """
  The oldest ClickHouse major version the server supports. Migrations refuse to
  run below it, and the self-hosting requirements publish it.
  """
  def minimum_supported_version, do: @minimum_supported_version

  @doc """
  The release CI installs to exercise `minimum_supported_version/0`.

  The oldest ClickHouse 25 still receiving upstream patches: 25.3 LTS stopped in
  February 2026. It also predates `deduplicate_insert_select`, so the job covers
  the version gate in `Tuist.ClickHouseCapabilities` rather than bypassing it.
  """
  def oldest_tested_release, do: @oldest_tested_release
end
