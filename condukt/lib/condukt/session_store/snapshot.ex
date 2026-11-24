defmodule Condukt.SessionStore.Snapshot do
  @moduledoc """
  Serializable session snapshot persisted by session stores.

  A snapshot carries its own `:version`, and that is the field that matters
  most. Once a snapshot exists on someone's disk the shape is no longer free to
  change, and a record that does not say which shape it is leaves no way to read
  an old one except guessing. `migrate/1` is the only supported way to turn a
  loaded term back into a snapshot, so every store gets the same handling
  whether it wrote the term yesterday or a year ago.

  `:id` and `:actor` exist for the same reason. A snapshot without them can be
  restored but not attributed, which is enough for a single user resuming their
  own terminal and not enough for anything that holds sessions on behalf of
  more than one person. `:actor` is opaque to Condukt: a host puts whatever
  identifies the owner in it and gets it back untouched.

  A session that keeps a journal also records which runs the snapshot holds
  and the outcomes of its recent request ids, with `put_runs/3`, read back
  with `runs/1`. They are not struct fields: a term with a field an older
  build has never seen is one that build cannot decode with
  `:erlang.binary_to_term(binary, [:safe])`, which would cost it the whole
  snapshot. They sit under a string key instead, encoded on their own, so an
  older build reads the snapshot and drops them on its next save, which
  forgets the stored request outcomes. A store that writes snapshots field by
  field must keep that entry too; `Condukt.SessionStore.Conformance` checks it.
  """

  require Logger

  @current_version 3

  defstruct version: @current_version,
            id: nil,
            actor: nil,
            messages: [],
            model: nil,
            thinking_level: nil,
            system_prompt: nil,
            created_at: nil,
            updated_at: nil

  @runs_key "condukt.runs"

  @doc "The snapshot version this build writes."
  def current_version, do: @current_version

  @doc """
  Records the newest run the snapshot's messages include, and the stored
  outcomes of recent request ids, newest first.
  """
  def put_runs(%__MODULE__{} = snapshot, last_run_id, requests) do
    Map.put(snapshot, @runs_key, :erlang.term_to_binary(%{"last_run_id" => last_run_id, "requests" => requests}))
  end

  @doc """
  Returns `{last_run_id, requests}` as recorded by `put_runs/3`, or
  `{nil, []}` for a snapshot without them or whose record cannot be read.
  """
  # Matches the struct as an open map: the runs record is a key the struct
  # type does not declare.
  def runs(%{__struct__: __MODULE__} = snapshot) do
    case Map.get(snapshot, @runs_key) do
      nil -> {nil, []}
      binary -> decode_runs(binary)
    end
  end

  defp decode_runs(binary) when is_binary(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %{"last_run_id" => last_run_id, "requests" => requests} when is_list(requests) -> {last_run_id, requests}
      _other -> unreadable_runs()
    end
  rescue
    ArgumentError -> unreadable_runs()
  end

  defp decode_runs(_other), do: unreadable_runs()

  defp unreadable_runs do
    Logger.warning("ignoring the unreadable run record of a session snapshot")
    {nil, []}
  end

  @doc """
  Builds a snapshot, stamping the version and timestamps.

  `:created_at` is preserved when given, so a session that has been persisted
  before keeps the moment it started rather than the moment it was last saved.
  """
  def new(fields) do
    now = DateTime.utc_now()

    struct!(
      __MODULE__,
      fields
      |> Map.new()
      |> Map.put(:version, @current_version)
      |> Map.put_new(:created_at, now)
      |> Map.put(:updated_at, now)
    )
  end

  @doc """
  Brings a loaded term up to the current version.

  Returns `{:ok, snapshot}` or `{:error, reason}`. Version 1 had no version
  field at all, so a struct without one is read as version 1 rather than
  rejected: those snapshots are on real disks and refusing them would lose
  conversations that are otherwise intact.
  """
  def migrate(%__MODULE__{} = snapshot) do
    snapshot |> Map.get(:version, 1) |> migrate_from(snapshot)
  end

  def migrate(_other), do: {:error, :invalid_snapshot}

  defp migrate_from(@current_version, snapshot), do: {:ok, snapshot}

  defp migrate_from(2, snapshot), do: {:ok, %{snapshot | version: @current_version}}

  # Version 1 carried messages, model, thinking level and system prompt, and
  # nothing that identified the session. There is nothing to recover those from,
  # so they stay nil and the caller supplies them if it cares.
  defp migrate_from(1, snapshot) do
    {:ok,
     struct!(__MODULE__, %{
       version: @current_version,
       messages: Map.get(snapshot, :messages, []),
       model: Map.get(snapshot, :model),
       thinking_level: Map.get(snapshot, :thinking_level),
       system_prompt: Map.get(snapshot, :system_prompt)
     })}
  end

  # A snapshot from a newer build than this one. Reading it would mean guessing
  # at fields this code has never seen, so it is refused rather than silently
  # truncated on the next save.
  defp migrate_from(version, _snapshot) when is_integer(version) and version > @current_version do
    {:error, {:unsupported_snapshot_version, version}}
  end

  defp migrate_from(_version, _snapshot), do: {:error, :invalid_snapshot}
end
