defmodule Pulse.Roles do
  @moduledoc """
  The work an instance takes on, from `PULSE_ROLES`: `ingest` (receivers),
  `query` (query, discovery, MCP and management APIs) and `maintenance`
  (compaction, retention, alert evaluation, error projection and reliability
  workers). An instance runs all three by default.

  Roles let operators run separate pools that scale independently on the same
  bucket. They are routing and supervision choices only: any instance with a
  role can serve any tenant, and correctness never depends on which instances
  run which roles.
  """

  @roles [:ingest, :query, :maintenance]

  @spec all() :: [atom()]
  def all, do: @roles

  @doc "Whether this instance runs `role`."
  @spec enabled?(atom()) :: boolean()
  def enabled?(role) when role in @roles, do: role in enabled()

  @spec enabled() :: [atom()]
  def enabled, do: Keyword.get(Pulse.Runtime.get_env(:pulse, __MODULE__, []), :roles, @roles)

  @doc "Parse a comma-separated role list; raises on unknown or empty lists."
  @spec parse!(String.t()) :: [atom()]
  def parse!(raw) when is_binary(raw) do
    names = raw |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    known = Map.new(@roles, &{Atom.to_string(&1), &1})

    case Enum.split_with(names, &Map.has_key?(known, &1)) do
      {[_ | _] = valid, []} -> valid |> Enum.map(&Map.fetch!(known, &1)) |> Enum.uniq()
      _ -> raise "PULSE_ROLES must list one or more of ingest, query, maintenance"
    end
  end
end
