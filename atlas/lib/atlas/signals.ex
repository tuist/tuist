defmodule Atlas.Signals do
  @moduledoc "Portable, permission-bound evidence feeding Automation and Orbit."
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Authorization
  alias Atlas.Automations
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainAccess
  alias Atlas.Automations.Revision
  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Repo
  alias Atlas.Signals.Config
  alias Atlas.Signals.Interface
  alias Atlas.Signals.MCPEvents
  alias Atlas.Signals.Polling
  alias Atlas.Signals.Routing
  alias Atlas.Signals.Signal
  alias Atlas.Signals.Source
  alias Atlas.Users
  alias Atlas.Users.User

  def create_source(actor, attrs, opts \\ []) do
    with :ok <- Automations.authorize(actor, :write),
         :ok <- Contract.validate(Interface.schema(:create_signal_source), attrs),
         true <- String.trim(attrs["name"]) != "",
         {:ok, revision_id} <- uuid(attrs["revision_id"]),
         %Revision{} = revision <- Repo.get(DomainAccess.scope(Revision, actor), revision_id),
         :ok <- DomainAccess.authorize_execution(actor, revision.plan),
         true <- Enum.all?(attrs["required_scopes"] || [], &(&1 in Authorization.all_scopes())),
         true <- Access.holds_all?(actor, attrs["required_scopes"] || []),
         true <- is_nil(attrs["event_receiver"]) or is_nil(attrs["polling"]),
         {:ok, readers} <- readers(actor, attrs["reader_ids"] || []) do
      Repo.transaction(fn ->
        signing_secret = if attrs["event_receiver"], do: :crypto.strong_rand_bytes(32)
        polling = Polling.bind(actor, attrs["polling"])

        source =
          %Source{owner_id: actor.id, revision_id: revision.id, signing_secret: signing_secret}
          |> Ecto.Changeset.change(polling)
          |> Source.changeset(Map.put(attrs, "reader_ids", readers))
          |> Repo.insert()
          |> case do
            {:ok, source} -> source
            {:error, _changeset} -> Repo.rollback(:invalid_source)
          end

        audit(actor, "signal_source.created", source.id, opts)
        %{source | delivery: MCPEvents.delivery(source)}
      end)
    else
      _ -> {:error, :invalid_source}
    end
  end

  def list(actor, params \\ %{}) do
    with :ok <- Automations.authorize(actor, :read),
         :ok <- Contract.validate(Interface.schema(:list_signals), params) do
      scopes = Users.scopes_for(actor)

      query =
        from s in Signal,
          join: source in Source,
          on: source.id == s.source_id,
          where: ^actor.id in source.reader_ids,
          where: fragment("?::text[] <@ ?::text[]", source.required_scopes, ^scopes),
          order_by: [
            asc: fragment("CASE ? WHEN 'now' THEN 0 WHEN 'today' THEN 1 WHEN 'later' THEN 2 ELSE 3 END", s.priority),
            asc: s.observed_at,
            asc: s.id
          ]

      query = if params["status"], do: where(query, [s], s.status == ^params["status"]), else: query
      {items, meta} = Flop.run(query, %Flop{page: params["page"] || 1, page_size: 20}, repo: Repo)
      {:ok, %{items: Enum.map(items, &receipt/1), total_count: meta.total_count}}
    end
  end

  def list_sources(actor, params \\ %{}) do
    with :ok <- Automations.authorize(actor, :read),
         :ok <- Contract.validate(Interface.schema(:list_signal_sources), params) do
      {items, meta} =
        from(s in Source, where: s.owner_id == ^actor.id, order_by: [desc: s.inserted_at, desc: s.id])
        |> Flop.run(%Flop{page: params["page"] || 1, page_size: 20}, repo: Repo)

      {:ok, %{items: items, total_count: meta.total_count}}
    end
  end

  def set_enabled(actor, id, enabled, opts \\ []) when is_boolean(enabled) do
    with :ok <- Automations.authorize(actor, :write),
         :ok <- require_enabled(enabled),
         {:ok, id} <- uuid(id) do
      Repo.transaction(fn ->
        source = source!(actor, id)
        source = source |> Ecto.Changeset.change(enabled: enabled) |> Repo.update!()
        audit(actor, "signal_source.updated", source.id, opts)
        source
      end)
    end
  end

  def ingest(actor, source_id, envelope, opts \\ []) do
    with :ok <- Automations.authorize(actor, :write),
         :ok <- require_enabled(true),
         {:ok, source_id} <- uuid(source_id),
         :ok <- Contract.validate(Interface.envelope_schema(), envelope),
         true <- String.trim(envelope["title"]) != "",
         true <- Contract.within_budget?(normalize_envelope(envelope), 12_000),
         {:ok, occurred_at, _offset} <- DateTime.from_iso8601(envelope["occurred_at"]) do
      Repo.transaction(fn ->
        source = source!(actor, source_id)
        receive_signal!(actor, source, normalize_envelope(envelope), occurred_at, opts)
      end)
    else
      false -> {:error, :invalid_envelope}
      {:error, _} = error -> error
    end
  end

  def get(actor, id) do
    with :ok <- Automations.authorize(actor, :read),
         {:ok, id} <- uuid(id),
         %Signal{} = signal <- Repo.get(Signal, id),
         %Source{} = source <- Repo.get(Source, signal.source_id),
         true <- actor.id in source.reader_ids and Access.holds_all?(actor, source.required_scopes) do
      {:ok, Map.merge(receipt(signal), %{envelope: decode(signal), decision: signal.decision})}
    else
      _ -> {:error, :not_found}
    end
  end

  def candidates(actor, id) do
    with {:ok, signal} <- get(actor, id) do
      source = Repo.get!(Source, signal.source_id)
      {:ok, %{candidates: Routing.candidates(source, signal.envelope)}}
    end
  end

  # Only opaque IDs and a bounded policy decision cross the workflow boundary.
  # Private evidence never becomes a broadly readable Automation input/output.
  def decide(actor, attrs, opts \\ []) do
    with :ok <- Automations.authorize(actor, :write),
         :ok <- require_enabled(true),
         :ok <- Contract.validate(Interface.decision_schema(), attrs),
         {:ok, id} <- uuid(attrs["signal_id"]) do
      Repo.transaction(fn ->
        signal = Repo.one(from s in Signal, where: s.id == ^id, lock: "FOR UPDATE")
        if is_nil(signal), do: Repo.rollback(:not_found)
        source = source!(actor, signal.source_id)
        record_decision!(source, signal, attrs, actor, opts)
      end)
    end
  end

  defp require_enabled(false), do: :ok
  defp require_enabled(true), do: if(Config.enabled?(), do: :ok, else: {:error, :signals_disabled})

  defp receive_signal!(actor, source, envelope, occurred_at, opts) do
    case Repo.get_by(Signal, source_id: source.id, external_id: envelope["external_id"]) do
      nil ->
        if not source.enabled, do: Repo.rollback(:source_disabled)
        signal = insert_signal!(source, envelope, occurred_at)
        admit_signal!(actor, source, signal, opts)

      existing ->
        if decode(existing) != envelope, do: Repo.rollback(:idempotency_conflict)
        receipt(existing)
    end
  end

  defp record_decision!(source, %Signal{status: "pending"} = signal, attrs, actor, opts) do
    if not source.enabled, do: Repo.rollback(:source_disabled)
    {thread_id, routed} = apply_decision!(source, signal, attrs)
    decision = attrs |> Map.take(~w(action priority reason)) |> Map.put("routing", routed)

    signal =
      signal
      |> Ecto.Changeset.change(
        status: attrs["action"],
        priority: attrs["priority"],
        decision: decision,
        thread_id: thread_id
      )
      |> Repo.update!()

    notify_opened!(source, signal, actor, opts)
    audit(actor, "signal.decided", signal.id, opts)
    receipt(signal)
  end

  defp record_decision!(_source, signal, attrs, _actor, _opts) do
    if Map.take(signal.decision, ~w(action priority reason)) != Map.take(attrs, ~w(action priority reason)),
      do: Repo.rollback(:idempotency_conflict)

    receipt(signal)
  end

  defp admit_signal!(actor, source, signal, opts) do
    revision = Repo.get!(Revision, source.revision_id)

    case Automations.admit(actor, revision, %{"signal_id" => signal.id}, "signal", "signal:#{signal.id}", opts) do
      {:ok, run} ->
        signal = signal |> Ecto.Changeset.change(execution_id: run.id) |> Repo.update!()
        audit(actor, "signal.received", signal.id, opts)
        receipt(signal)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp notify_opened!(source, %Signal{status: "opened"} = signal, actor, opts) do
    recipients = Enum.uniq([source.owner_id | Enum.map(signal.decision["routing"], & &1.id)])

    Enum.each(recipients, fn user_id ->
      {:ok, _} =
        Atlas.Push.notify_user(user_id, "orbit_signal", {"orbit", signal.thread_id},
          signal_id: signal.id,
          actor: actor,
          interface: Keyword.get(opts, :interface, "worker")
        )
    end)
  end

  defp notify_opened!(_source, _signal, _actor, _opts), do: :ok

  defp apply_decision!(_source, _signal, %{"action" => "ignored"}), do: {nil, []}

  defp apply_decision!(source, signal, attrs) do
    envelope = decode(signal)
    candidates = Routing.candidates(source, envelope)
    routed = Enum.map(candidates, &Map.take(&1, [:id, :reason, :matches]))

    body =
      "Untrusted signal evidence: #{envelope["summary"]}\n\n" <>
        JSON.encode!(%{
          "evidence" => Map.delete(envelope, "summary"),
          "priority" => attrs["priority"],
          "reason" => attrs["reason"],
          "routing" => Enum.map(routed, &Map.delete(&1, :matches))
        })

    correlation = :crypto.hash(:sha256, signal.correlation_key) |> Base.encode16(case: :lower)

    case Orbit.open_for_signal(%{
           owner_id: source.owner_id,
           participant_ids: Enum.map(candidates, & &1.id),
           source_type: "signal_source",
           source_id: source.id <> ":" <> correlation,
           title: envelope["title"],
           summary: envelope["summary"],
           priority: attrs["priority"],
           body: body,
           required_scopes: source.required_scopes,
           signal_reader_ids: source.reader_ids
         }) do
      {:ok, thread} -> {thread.id, routed}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp insert_signal!(source, envelope, occurred_at) do
    Repo.insert!(%Signal{
      source_id: source.id,
      external_id: envelope["external_id"],
      correlation_key: envelope["correlation_key"],
      type: envelope["type"],
      schema_version: envelope["schema_version"],
      occurred_at: DateTime.from_unix!(DateTime.to_unix(occurred_at, :microsecond), :microsecond),
      observed_at: DateTime.utc_now(),
      envelope: JSON.encode!(envelope)
    })
  end

  defp normalize_envelope(envelope), do: Map.merge(%{"subjects" => [], "topics" => [], "data" => %{}}, envelope)

  defp decode(signal), do: JSON.decode!(signal.envelope)

  defp source!(actor, id) do
    source = Repo.one(from s in Source, where: s.id == ^id, lock: "FOR UPDATE")

    if is_nil(source) or source.owner_id != actor.id or not Access.holds_all?(actor, source.required_scopes),
      do: Repo.rollback(:not_found)

    source
  end

  defp readers(actor, ids) do
    ids = Enum.uniq([actor.id | ids])

    if Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) and
         Repo.aggregate(from(u in User, where: u.id in ^ids), :count) == length(ids),
       do: {:ok, ids},
       else: {:error, :invalid_readers}
  end

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp receipt(signal),
    do: Map.take(signal, [:id, :source_id, :status, :priority, :thread_id, :execution_id, :observed_at])

  defp audit(actor, action, id, opts) do
    target_type = if String.starts_with?(action, "signal_source."), do: "signal_source", else: "signal"

    Audit.record(action, %{target_type: target_type, target_id: id},
      actor: actor,
      interface: Keyword.get(opts, :interface, "worker")
    )
  end
end
