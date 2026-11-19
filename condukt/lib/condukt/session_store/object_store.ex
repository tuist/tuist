defmodule Condukt.SessionStore.ObjectStore do
  @moduledoc """
  A `Condukt.SessionStore` with a journal, on object storage such as S3 or
  Tigris, that fences out a writer that lost its session.

      session_store:
        {Condukt.SessionStore.ObjectStore,
         bucket: {Condukt.SessionStore.ObjectStore.S3, endpoint: ..., bucket: ..., ...},
         key: "thread-123",
         epoch: 7}

  ## Options

    * `:bucket` - required, `{module, config}` for a
      `Condukt.SessionStore.ObjectStore.Bucket`.
    * `:key` - the session's key, falling back to the session's `:id`. Letters,
      digits, `.`, `_`, `:`, and `-`.
    * `:prefix` - where sessions live in the bucket, `"condukt/sessions"` by
      default.
    * `:epoch` - the writer's epoch, a non-negative integer, `0` by default.
      Whatever hands a session to a process, such as a lease, gives each new
      owner a higher epoch than the last.
    * `:encrypt` and `:decrypt` - functions from binary to binary applied to
      every object, the identity by default.

  ## Layout

  Every object is created once and never overwritten; S3 refuses a create
  whose key exists (`If-None-Match: *`), and that refusal is the only
  coordination the store needs. Under `<prefix>/<key>/`:

    * `manifest/<n>` - the session's state at version `n`: the writer epoch,
      the snapshot without its messages, the segments holding the messages,
      and `wal_from`, where the journal starts. The highest `n` is current.
    * `segments/<first message>-<epoch>-<random>` - a run of messages. A save
      adds one segment with the messages after the stored ones, so a run costs
      what it added, not the whole history. A history that no longer starts
      with the stored messages, as after a compaction, or one spread over too
      many segments, is written as a single segment again.
    * `wal/<n>` - journal records, one object per append, from `wal_from` on.
      Clearing the journal moves `wal_from` past them.

  ## Fencing

  A process writing with a higher epoch than the current manifest's first
  creates the next manifest with its epoch, then creates an empty fence
  object at the next free `wal/<n>`, and reads the journal only after that.
  A writer with an older epoch is refused from then on:

    * its next manifest is taken, so a save or clear fails with
      `{:error, :fenced}`;
    * its next journal object is the fence, so an append fails the same way;
    * after every append and every manifest it creates, it checks that no
      manifest follows its own. That catches the cases where a newer writer
      has since cleared the journal, deleting the fence, or deleted the
      manifest the old writer's next one would have collided with, which
      would let its creates succeed where nobody reads them. A manifest that
      turns out to be superseded refuses the save or clear, which then
      deletes nothing.

  A record the old writer created before the fence is read by the new writer,
  so a record the old writer was told is durable is never lost. One it
  created after the new writer's manifest but before the fence is read too,
  though the old writer is told the append failed: the new writer then holds
  a tool call's intent without its result, which a resumed run already treats
  as an outcome it cannot know.

  An append costs one create and one listing. A save costs a segment create,
  a manifest create, and a listing.

  `load/1` and `load_journal/1` take the session over first when `:epoch` is
  given, as a write would, and are plain reads of the current state otherwise,
  for readers that never write. A read at an epoch must not run alongside a
  write at the same epoch from another process: its fence object takes the
  writer's next journal position. Read before writing, or from the writer.

  The writer's position (current manifest and next journal object) is cached
  in the writing process, which is the session, and only by writes. A write
  from a stale position is refused like a stale writer's, and the cache is
  dropped after any failed write.

  A writer that takes the session over deletes the manifests before its
  claim, and later each one it replaced but the last two; the check above
  needs only that some manifest after an old writer's own exists. Objects a fenced writer created before it found out,
  the journal's fence objects until the journal is cleared, and anything a
  failed delete left behind are not referenced and stay in the bucket.
  """

  @behaviour Condukt.SessionStore

  @prefix "condukt/sessions"
  @max_segments 32
  @read_attempts 3
  @claim_attempts 3

  @impl true
  def load(opts) do
    ctx = context(opts)

    retrying(fn ->
      with {:ok, manifest} <- read_manifest(ctx, opts), do: read_snapshot(ctx, manifest)
    end)
  end

  defp read_snapshot(_ctx, %{header: nil}), do: :not_found

  defp read_snapshot(ctx, %{header: header, segments: segments}) do
    with {:ok, parts} <- read_all(ctx, Enum.map(segments, & &1.key), [:safe]) do
      {:ok, %{header | messages: Enum.concat(parts)}}
    end
  end

  @impl true
  def save(snapshot, opts) do
    ctx = context(opts)

    with {:ok, writer} <- open(ctx) do
      %{segments: stored} = manifest = writer.manifest
      digests = Enum.map(snapshot.messages, &digest/1)
      count = Enum.sum(Enum.map(stored, & &1.count))

      kept? =
        length(stored) < @max_segments and count <= length(digests) and
          chain(Enum.take(digests, count)) == manifest.digest

      {base, from} = if kept?, do: {stored, count}, else: {[], 0}

      with {:ok, segments} <- add_segment(ctx, base, from, Enum.drop(snapshot.messages, from)),
           {:ok, _writer} <-
             commit(ctx, writer, %{
               manifest
               | header: %{snapshot | messages: []},
                 segments: segments,
                 digest: chain(digests)
             }) do
        delete_all(ctx, Enum.map(stored -- segments, & &1.key))
      end
    end
  end

  @impl true
  def clear(opts) do
    ctx = context(opts)

    with {:ok, writer} <- open(ctx),
         {:ok, _writer} <- commit(ctx, writer, %{writer.manifest | header: nil, segments: [], digest: nil}) do
      delete_all(ctx, Enum.map(writer.manifest.segments, & &1.key))
    end
  end

  @impl true
  def append_journal(records, opts) do
    ctx = context(opts)

    with {:ok, writer} <- open(ctx) do
      with :ok <- create(ctx, wal_key(ctx, writer.wal_next), encode(ctx, {:records, records})),
           :ok <- check_superseded(ctx, writer.seq) do
        remember(ctx, %{writer | wal_next: writer.wal_next + 1})
        :ok
      else
        # Only this writer appends at its epoch, so someone else's object at
        # its next position is a newer writer's fence.
        {:error, :exists} ->
          forget(ctx)
          {:error, :fenced}

        {:error, :fenced} ->
          forget(ctx)
          {:error, :fenced}

        error ->
          forget(ctx)
          error
      end
    end
  end

  @impl true
  def load_journal(opts) do
    ctx = context(opts)

    retrying(fn ->
      with {:ok, manifest} <- read_manifest(ctx, opts),
           {:ok, keys} <- list(ctx, "wal/", wal_key(ctx, manifest.wal_from - 1)),
           {:ok, entries} <- read_all(ctx, keys, []) do
        {:ok, Enum.flat_map(entries, &journal_records/1)}
      end
    end)
  end

  @impl true
  def clear_journal(opts) do
    ctx = context(opts)

    case open(ctx) do
      {:ok, %{manifest: %{wal_from: from}, wal_next: from}} -> :ok
      {:ok, writer} -> move_journal_start(ctx, writer)
      error -> error
    end
  end

  defp move_journal_start(ctx, writer) do
    from = writer.manifest.wal_from
    to = writer.wal_next

    with {:ok, _writer} <- commit(ctx, writer, %{writer.manifest | wal_from: to}) do
      delete_journal(ctx, from, to)
    end
  end

  # The journal starts at `to` now, so what a failed listing leaves behind is
  # no longer read.
  defp delete_journal(ctx, from, to) do
    case list(ctx, "wal/", wal_key(ctx, from - 1)) do
      {:ok, keys} -> delete_all(ctx, Enum.filter(keys, &(&1 < wal_key(ctx, to))))
      {:error, _reason} -> :ok
    end
  end

  defp journal_records({:records, records}), do: records
  defp journal_records({:fence, _epoch}), do: []

  ## Writer

  # A read at an epoch takes the session over like a write, so it sees every
  # record an older writer can still have made durable, but leaves no writer
  # cached: the reading process, such as the supervisor that starts the
  # session, is often not the one that writes, and a position it kept would be
  # stale by the time it read again at the same epoch.
  defp read_manifest(ctx, opts) do
    if Keyword.has_key?(opts, :epoch) do
      with {:ok, writer} <- fence(ctx) do
        forget(ctx)
        {:ok, writer.manifest}
      end
    else
      with {:ok, {_seq, manifest}} <- latest(ctx), do: {:ok, manifest}
    end
  end

  defp open(ctx) do
    case Process.get(cache_key(ctx)) do
      nil -> fence(ctx)
      writer -> {:ok, writer}
    end
  end

  # Takes the session over: the manifest first, so an older writer's next
  # manifest is refused, then the journal, so its next append is refused too.
  # The fence is written by a writer that already holds the epoch as well, in
  # case it stopped between the two.
  # A claim that loses to the older writer's own next manifest reads the new
  # latest one and claims after it.
  defp fence(ctx, attempt \\ 1) do
    with {:ok, {seq, manifest}} <- latest(ctx),
         :ok <- check_epoch(ctx, manifest),
         {:ok, writer} <- claim(ctx, %{seq: seq, manifest: manifest, wal_next: nil}),
         {:ok, keys} <- list(ctx, "wal/", wal_key(ctx, manifest.wal_from - 1)),
         {:ok, wal_next} <- create_fence(ctx, next_number(keys, manifest.wal_from)) do
      {:ok, remember(ctx, %{writer | wal_next: wal_next})}
    else
      {:error, :conflict} when attempt < @claim_attempts -> fence(ctx, attempt + 1)
      error -> error
    end
  end

  defp check_epoch(ctx, manifest) do
    if manifest.epoch > ctx.epoch, do: {:error, :fenced}, else: :ok
  end

  defp claim(ctx, writer) do
    if writer.manifest.epoch < ctx.epoch do
      with {:ok, writer} <- commit(ctx, writer, %{writer.manifest | epoch: ctx.epoch}) do
        delete_manifests_before(ctx, writer.seq)
        {:ok, writer}
      end
    else
      {:ok, writer}
    end
  end

  # The manifests before a claim are no longer read: the previous writer
  # checks for the claim's own manifest, which stays. Only a writer two or
  # more owners back, whose lease ended long before, would check for one of
  # them, and the journal's fence objects still refuse its appends.
  defp delete_manifests_before(ctx, seq) do
    case list(ctx, "manifest/", nil) do
      {:ok, keys} -> delete_all(ctx, Enum.filter(keys, &(&1 < manifest_key(ctx, seq))))
      {:error, _reason} -> :ok
    end
  end

  # The older writer may create the object we aimed at first, which leaves
  # its record in the journal before the fence.
  defp create_fence(ctx, number) do
    case create(ctx, wal_key(ctx, number), encode(ctx, {:fence, ctx.epoch})) do
      :ok -> {:ok, number + 1}
      {:error, :exists} -> create_fence(ctx, number + 1)
      error -> error
    end
  end

  defp next_number([], from), do: from
  defp next_number(keys, _from), do: keys |> List.last() |> number() |> Kernel.+(1)

  defp commit(ctx, writer, manifest) do
    seq = writer.seq + 1

    case create(ctx, manifest_key(ctx, seq), encode(ctx, manifest)) do
      # A newer writer may have deleted the manifests this one would have
      # collided with, so a create that succeeds is only this writer's if no
      # manifest follows it. The caller deletes nothing otherwise.
      :ok ->
        with :ok <- check_superseded(ctx, seq), do: committed(ctx, writer, seq, manifest)

      {:error, :exists} ->
        forget(ctx)

        case latest(ctx) do
          {:ok, {_seq, %{epoch: epoch}}} when epoch > ctx.epoch -> {:error, :fenced}
          {:ok, _} -> {:error, :conflict}
          error -> error
        end

      error ->
        forget(ctx)
        error
    end
  end

  defp committed(ctx, writer, seq, manifest) do
    if seq > 2, do: delete_all(ctx, [manifest_key(ctx, seq - 2)])
    {:ok, remember(ctx, %{writer | seq: seq, manifest: manifest})}
  end

  defp latest(ctx) do
    case list(ctx, "manifest/", nil) do
      {:ok, []} ->
        {:ok, {0, %{epoch: 0, wal_from: 1, header: nil, segments: [], digest: nil}}}

      {:ok, keys} ->
        key = List.last(keys)

        with {:ok, manifest} <- read(ctx, key, [:safe]), do: {:ok, {number(key), manifest}}

      error ->
        error
    end
  end

  defp add_segment(_ctx, segments, _from, []), do: {:ok, segments}

  defp add_segment(ctx, segments, from, messages) do
    random = 6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    key = ctx.root <> "segments/" <> pad(from) <> "-#{ctx.epoch}-" <> random

    with :ok <- create(ctx, key, encode(ctx, messages)) do
      {:ok, segments ++ [%{key: key, from: from, count: length(messages)}]}
    end
  end

  defp remember(ctx, writer) do
    Process.put(cache_key(ctx), writer)
    writer
  end

  defp forget(ctx), do: Process.delete(cache_key(ctx))

  defp cache_key(ctx), do: {__MODULE__, ctx.bucket, ctx.root, ctx.epoch}

  ## Objects

  # A create retried after its response was lost finds its own object, which
  # is a success, not a conflict.
  defp create(ctx, key, body) do
    {module, config} = ctx.bucket

    case module.create(config, key, body) do
      {:error, :exists} ->
        case module.get(config, key) do
          {:ok, ^body} -> :ok
          _ -> {:error, :exists}
        end

      result ->
        result
    end
  end

  # Any manifest after the writer's own is a newer writer's: the current
  # writer's manifests are never all deleted, so however far behind this
  # writer is, it finds one.
  defp check_superseded(ctx, seq) do
    case list(ctx, "manifest/", manifest_key(ctx, seq)) do
      {:ok, []} ->
        :ok

      {:ok, _newer} ->
        forget(ctx)
        {:error, :fenced}

      error ->
        forget(ctx)
        error
    end
  end

  defp read(ctx, key, decode_opts) do
    {module, config} = ctx.bucket

    case module.get(config, key) do
      {:ok, body} -> decode(ctx, body, decode_opts)
      :not_found -> {:error, :missing}
      error -> error
    end
  end

  defp read_all(ctx, keys, decode_opts) do
    keys
    |> Task.async_stream(&read(ctx, &1, decode_opts), max_concurrency: 16, timeout: 60_000)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, term}}, {:ok, acc} -> {:cont, {:ok, [term | acc]}}
      {:ok, error}, _acc -> {:halt, error}
      {:exit, reason}, _acc -> {:halt, {:error, {:read_failed, reason}}}
    end)
    |> case do
      {:ok, terms} -> {:ok, Enum.reverse(terms)}
      error -> error
    end
  end

  defp list(ctx, dir, start_after) do
    {module, config} = ctx.bucket
    module.list(config, ctx.root <> dir, start_after)
  end

  # Deleting is cleanup: what it misses is no longer referenced.
  defp delete_all(ctx, keys) do
    {module, config} = ctx.bucket

    keys
    |> Task.async_stream(&module.delete(config, &1), max_concurrency: 16, timeout: 60_000, on_timeout: :kill_task)
    |> Stream.run()
  end

  # A writer deletes what the manifest it replaced referenced, so a reader
  # holding that manifest can find an object gone. It reads again.
  defp retrying(fun, attempt \\ 1) do
    case fun.() do
      {:error, :missing} when attempt < @read_attempts -> retrying(fun, attempt + 1)
      result -> result
    end
  end

  ## Encoding

  defp encode(ctx, term), do: ctx.encrypt.(:erlang.term_to_binary(term))

  # Journal records are decoded without `:safe`, like the disk store's: one can
  # hold an atom the VM has not created yet, such as a tool's error reason.
  defp decode(ctx, body, decode_opts) do
    {:ok, body |> ctx.decrypt.() |> :erlang.binary_to_term(decode_opts)}
  rescue
    _ -> {:error, :undecodable}
  end

  # A running digest of the stored messages, so a save can tell whether the
  # history still starts with them without reading them back.
  defp digest(message), do: :crypto.hash(:sha256, :erlang.term_to_binary(message, [:deterministic]))
  defp chain([]), do: nil
  defp chain(digests), do: Enum.reduce(digests, "", &:crypto.hash(:sha256, &2 <> &1))

  ## Keys

  defp context(opts) do
    key = Keyword.get(opts, :key) || Keyword.get(opts, :id) || raise ArgumentError, "a session key is required"
    prefix = Keyword.get(opts, :prefix, @prefix)
    epoch = Keyword.get(opts, :epoch, 0)

    if !is_binary(key) or !Regex.match?(~r/\A[A-Za-z0-9._:\-]+\z/, key),
      do: raise(ArgumentError, "session key #{inspect(key)} has characters an object key cannot carry unencoded")

    if !Regex.match?(~r/\A[A-Za-z0-9._:\-\/]*\z/, prefix),
      do: raise(ArgumentError, "prefix #{inspect(prefix)} has characters an object key cannot carry unencoded")

    if !is_integer(epoch) or epoch < 0, do: raise(ArgumentError, "epoch must be a non-negative integer")

    %{
      bucket: Keyword.fetch!(opts, :bucket),
      root: Enum.join(Enum.reject([String.trim(prefix, "/"), key], &(&1 == "")), "/") <> "/",
      epoch: epoch,
      encrypt: Keyword.get(opts, :encrypt, & &1),
      decrypt: Keyword.get(opts, :decrypt, & &1)
    }
  end

  defp manifest_key(ctx, seq), do: ctx.root <> "manifest/" <> pad(seq)
  defp wal_key(ctx, number), do: ctx.root <> "wal/" <> pad(number)

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(20, "0")
  defp number(key), do: key |> String.slice(-20, 20) |> String.to_integer()
end
