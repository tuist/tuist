defmodule Tuist.ClickHouseCapabilities do
  @moduledoc """
  Runtime capability checks for the ClickHouse instance a repo is connected to.

  The command_events migrations used to branch on `Tuist.Environment.tuist_hosted?/0`
  to decide whether ClickHouse features needing coordination were available. That
  conflates two unrelated things: whether this is the Tuist-operated product, and
  whether the ClickHouse behind it is the managed instance. Every preview
  environment is hosted yet migrates a brand-new single-node ClickHouse with no
  Keeper, so the assumption broke there and took the migration down with it. Ask
  the server what it supports instead.
  """

  alias Tuist.Environment

  @deduplicate_insert_select_since [26, 1]

  @doc """
  Whether `generateSerialID/1` is usable against `repo`, which requires a
  configured ClickHouse Keeper (or ZooKeeper); without one it raises
  `NO_ELEMENTS_IN_CONFIG`. ClickHouse only attaches `system.zookeeper_connection`
  when coordination is configured, so its presence is the cheapest
  side-effect-free signal.
  """
  def serial_ids_supported?(repo) do
    case repo.query("SELECT count() FROM system.tables WHERE database = 'system' AND name = 'zookeeper_connection'") do
      {:ok, %{rows: [[count]]}} ->
        count > 0

      {:error, error} ->
        # Guessing here would reintroduce the failure this check exists to
        # prevent: assume Keeper and the migration dies on a server without one,
        # assume no Keeper and the managed instance quietly gets random legacy
        # IDs instead of serial ones.
        raise "Could not determine whether ClickHouse supports serial IDs: #{Exception.message(error)}"
    end
  end

  @doc """
  The version of the ClickHouse server behind `repo`, as a list of integers.

  `version/0` is a plain function rather than a system table, so unlike the
  `system.*` reads elsewhere in this module it also answers inside a ClickHouse
  transaction, which is what the Ecto sandbox wraps every test in.
  """
  def server_version(repo) do
    case repo.query("SELECT version()") do
      {:ok, %{rows: [[version]]}} ->
        version
        |> String.split(".")
        |> Enum.take_while(&numeric?/1)
        |> Enum.map(&String.to_integer/1)

      {:error, error} ->
        raise "Could not determine the ClickHouse server version: #{Exception.message(error)}"
    end
  end

  defp numeric?(version_component), do: match?({_integer, ""}, Integer.parse(version_component))

  @doc """
  Settings that make an `INSERT SELECT` deduplicate against its
  `insert_deduplication_token`, so a retried insert cannot duplicate rows.

  `deduplicate_insert_select` arrived in ClickHouse 26.1, where `force_enable`
  raises instead of silently skipping deduplication when the server judges the
  select unstable. Earlier releases in the supported range reject the name with
  `UNKNOWN_SETTING`, and deduplicate `INSERT SELECT` whenever `insert_deduplicate`
  is on, which is the behaviour `force_enable` asks for.
  """
  def insert_select_deduplication_settings(repo) do
    if Enum.take(server_version(repo), 2) >= @deduplicate_insert_select_since do
      [deduplicate_insert_select: "force_enable"]
    else
      []
    end
  end

  @doc """
  Whether command_events should hand out Keeper-backed serial legacy IDs.

  Dev and test opt out even though their ClickHouse runs a Keeper (the local
  server enables it so tests can use transactions): local databases stay on the
  random default rather than taking a coordination round-trip per insert.
  Everywhere else this follows what the server can actually do.
  """
  def use_serial_ids?(repo) do
    if Environment.dev?() or Environment.test?() do
      false
    else
      serial_ids_supported?(repo)
    end
  end
end
