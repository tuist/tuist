defmodule Pulse.Alerting.Repository do
  @moduledoc "S3 rule authority, immutable revision audit chain, and bounded committed transition history."
  alias Pulse.Alerting.{Canonical, Principal, Recording, Rule, Targets}
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  @tail_limit 64
  @page_limit 32
  @receipt_limit 128
  @max_object_bytes 1_048_576
  @inline_limit 131_072

  def load(tenant, id, opts \\ []) do
    with :ok <- identifiers(tenant, id),
         {:ok, store, config} <- backend(opts),
         {:ok, etag, bytes} <- store.get_bounded(config, base(tenant, id) <> "/head.json", nil, @max_object_bytes),
         {:ok, head} <- decode(bytes),
         true <- valid_head?(head, tenant, id) do
      {:ok, head, etag}
    else
      false -> {:error, :integrity_error}
      error -> error
    end
  end

  def revision(tenant, id, ref, opts \\ []) do
    with :ok <- identifiers(tenant, id),
         %{"key" => key, "digest" => digest, "bytes" => size} <- ref,
         true <-
           is_binary(key) and String.starts_with?(key, base(tenant, id) <> "/g/") and
             is_binary(digest) and is_integer(size) and size in 1..@max_object_bytes,
         {:ok, store, config} <- backend(opts),
         {:ok, _etag, bytes} <- store.get_bounded(config, key, nil, size),
         true <-
           byte_size(bytes) == size and Canonical.digest(bytes) == digest and
             String.ends_with?(key, "/#{digest}.json"),
         {:ok, object} <- decode(bytes),
         true <- object["tenant"] == tenant and object["id"] == id do
      {:ok, object}
    else
      false -> {:error, :integrity_error}
      {:error, :not_found} -> {:error, :committed_object_unavailable}
      {:error, :response_too_large} -> {:error, :integrity_error}
      {:error, _} = error -> error
      _ -> {:error, :integrity_error}
    end
  end

  def change(principal, id, action, rule, params, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:rules:write", Rule.classification(rule)),
         :ok <- identifiers(principal.tenant, id),
         :ok <- mutation_parameters(params),
         {:ok, old, etag} <- existing(principal.tenant, id, opts),
         :ok <- authorize_old(principal, old, opts) do
      request =
        %{
          "action" => action,
          "id" => id,
          "tenant" => principal.tenant,
          "principal" => principal.id,
          "rule" => if(action != "delete", do: rule),
          "expected_revision" => params["expected_revision"],
          "operation_id" => params["operation_id"],
          "reason" => params["reason"],
          "restored_from" => params["restored_from"]
        }

      context = %{
        principal: principal,
        id: id,
        action: action,
        rule: rule,
        params: params,
        request: request,
        old: old,
        etag: etag,
        opts: opts
      }

      change_result(find_receipt(old, params["operation_id"]), context)
    end
  end

  def history(tenant, id, from, limit, opts \\ []) do
    with {:ok, head, _} <- load(tenant, id, opts),
         true <- is_integer(limit) and limit in 1..100 do
      # Non-nil refs are authenticated frozen-tip continuations supplied by the service,
      # never raw client object paths. Snapshots are not garbage-collected in this first version.
      walk(tenant, id, from || head["revision"], limit, [], opts)
    else
      false -> {:error, :invalid_arguments}
      error -> error
    end
  end

  def events(tenant, id, after_seq, limit, opts \\ []) do
    with {:ok, head, _} <- load(tenant, id, opts),
         true <- is_integer(after_seq) and after_seq >= 0 and is_integer(limit) and limit in 1..100,
         true <- after_seq >= head["history_floor"] - 1,
         true <- after_seq <= head["event_seq"] do
      refs = Enum.filter(head["pages"], &(&1["last"] > after_seq))
      read_events(tenant, id, refs, head["tail"], after_seq, limit, [], opts)
    else
      false -> {:error, :invalid_or_expired_position}
      error -> error
    end
  end

  def checkpoint(tenant, id, {head, etag}, evaluation, opts \\ []) do
    %{revision: revision_digest, timestamp: timestamp, instances: instances, health: health, events: events} =
      evaluation

    cond do
      head["revision"]["digest"] != revision_digest ->
        {:error, :conflict}

      head["state"] != "active" ->
        {:error, :rule_disabled}

      timestamp <= String.to_integer(head["completed_at_ns"]) ->
        {:error, :stale_evaluation}

      true ->
        with {:ok, next} <- append_events(head, events, opts),
             {:ok, next} <- enqueue_recording(next, Map.get(evaluation, :recording), opts) do
          next =
            Map.merge(next, %{
              "completed_at_ns" => Integer.to_string(timestamp),
              "instances" => instances,
              "health" => health,
              "evaluation_revision" => revision_digest
            })

          write_head(tenant, id, next, etag, opts)
        end
    end
  end

  defp enqueue_recording(head, nil, _opts), do: {:ok, head}

  defp enqueue_recording(head, result, opts) do
    queue = Map.get(head, "recording_queue", [])
    head = Map.put(head, "recording_series", result["next_series"])

    head =
      if Map.has_key?(result, "rule_health"),
        do: Map.put(head, "recording_rules", result["rule_health"]),
        else: head

    object =
      Map.merge(Map.drop(result, ["next_series", "rule_health"]), %{
        "schema_version" => 1,
        "tenant" => head["tenant"],
        "id" => head["id"],
        "generation" => head["generation"],
        "revision" => head["revision"]
      })

    bytes = Canonical.encode(object)

    cond do
      result["samples"] == [] ->
        {:ok, head}

      length(queue) >= 64 ->
        {:error, :recording_backlog}

      byte_size(bytes) > @max_object_bytes ->
        {:error, :invalid_recording_result}

      # A small group intent rides in the head write that commits it, saving
      # one Class A PUT per tick and leaving no object behind once published.
      # Single recordings keep immutable objects that older readers accept.
      Map.has_key?(head, "recording_rules") and inline_bytes(queue) + byte_size(bytes) <= @inline_limit ->
        ref = %{"digest" => Canonical.digest(bytes), "bytes" => byte_size(bytes), "inline" => object}
        {:ok, Map.put(head, "recording_queue", queue ++ [ref])}

      true ->
        with {:ok, ref} <- immutable(head["tenant"], head["id"], head["generation"], "recordings", object, opts),
             do: {:ok, Map.put(head, "recording_queue", queue ++ [ref])}
    end
  end

  defp inline_bytes(queue), do: Enum.sum(for %{"inline" => _, "bytes" => bytes} <- queue, do: bytes)

  @doc "A committed recording intent, carried inline by the head or stored as an immutable object."
  def recording_object(tenant, id, %{"inline" => object, "digest" => digest, "bytes" => size}, _opts) do
    bytes = Canonical.encode(object)

    if is_map(object) and byte_size(bytes) == size and Canonical.digest(bytes) == digest and
         object["tenant"] == tenant and object["id"] == id,
       do: {:ok, object},
       else: {:error, :integrity_error}
  end

  def recording_object(tenant, id, ref, opts), do: revision(tenant, id, ref, opts)

  @doc false
  def ack_recording(tenant, id, ref, opts \\ []) do
    with {:ok, head, etag} <- load(tenant, id, opts),
         do: ack_recording_head(tenant, id, {head, etag}, ref, opts)
  end

  defp ack_recording_head(tenant, id, {head, etag}, ref, opts) do
    case Map.get(head, "recording_queue", []) do
      [^ref | rest] ->
        events = if opts[:recording_event], do: [opts[:recording_event]], else: []

        with {:ok, next} <- append_events(head, events, opts),
             next = Map.put(next, "recording_queue", rest),
             next = next |> Map.put("recording_last", opts[:recording_progress]) |> Map.delete("recording_error"),
             {:ok, _} <- write_head(tenant, id, next, etag, opts),
             do: :ok

      queue ->
        # A competing consumer may already have acknowledged this same
        # immutable result. Never remove the next result on a stale ack.
        if ref in queue, do: {:error, :recording_conflict}, else: :ok
    end
  end

  @doc false
  def recording_error(tenant, id, ref, reason, opts \\ []) do
    with {:ok, head, etag} <- load(tenant, id, opts) do
      error = %{"digest" => ref["digest"], "reason" => reason}

      if List.first(Map.get(head, "recording_queue", [])) == ref and head["recording_error"] != error,
        do: write_head(tenant, id, Map.put(head, "recording_error", error), etag, opts),
        else: :ok
    end
  end

  def list(tenant, opts \\ []) do
    with true <- Principal.valid_id?(tenant),
         {:ok, store, config} <- backend(opts),
         {:ok, prefixes} <- store.list_prefixes(config, "tenants/#{tenant}/alerting/v1/rules/") do
      {:ok,
       Enum.map(prefixes, fn prefix -> prefix |> String.trim_trailing("/") |> String.split("/") |> List.last() end)}
    else
      false -> {:error, :invalid_id}
      error -> error
    end
  end

  defp bind_targets(_tenant, _rule, "delete", old) when is_map(old), do: {:ok, Map.get(old, "notification_targets", [])}
  defp bind_targets(tenant, rule, _action, _old), do: Targets.bind(tenant, Map.get(rule, "notification_targets", []))

  defp request_digest(request, targets) do
    targets = if request["action"] == "delete", do: [], else: targets
    request |> Map.put("notification_targets", targets) |> Canonical.hash()
  end

  defp change_result(%{"request_digest" => digest, "revision" => ref}, ctx) do
    # Preserve the existing digest format, but replay against the committed
    # bindings, never today's disposable target configuration. Authorization
    # and exact caller identity still precede returning the saved revision.
    with {:ok, snapshot} <- revision(ctx.principal.tenant, ctx.id, ref, ctx.opts),
         true <- request_digest(ctx.request, snapshot["notification_targets"]) == digest do
      {:ok, Map.put(snapshot, "revision", ref["digest"])}
    else
      false -> {:error, :operation_reused}
      error -> error
    end
  end

  defp change_result(nil, ctx) do
    if ctx.old && ctx.params["expected_revision"] != ctx.old["revision"]["digest"] do
      resolve_ancestry(
        ctx.principal.tenant,
        ctx.id,
        ctx.old["revision"],
        ctx.params["expected_revision"],
        ctx.params["operation_id"],
        ctx.request,
        128,
        ctx.opts
      )
    else
      publish_change(ctx)
    end
  end

  defp mutation_precondition(old, action, expected) do
    current = if old, do: old["revision"]["digest"]

    case expected == current do
      true -> mutation_state(old, action)
      false -> {:error, :conflict}
    end
  end

  defp mutation_state(nil, "create"), do: :ok
  defp mutation_state(nil, _), do: {:error, :not_found}
  defp mutation_state(%{"state" => "deleted"}, action) when action in ["create", "restore"], do: :ok
  defp mutation_state(%{"state" => "deleted"}, _), do: {:error, :not_found}
  defp mutation_state(_, "create"), do: {:error, :conflict}
  defp mutation_state(_, _), do: :ok

  defp publish_change(ctx) do
    with :ok <- mutation_precondition(ctx.old, ctx.action, ctx.params["expected_revision"]),
         {:ok, targets} <- bind_targets(ctx.principal.tenant, ctx.rule, ctx.action, ctx.old) do
      ctx = Map.merge(ctx, %{targets: targets, digest: request_digest(ctx.request, targets)})
      generation = generation(ctx.old, ctx.action)
      head = ctx.old || empty(ctx.principal.tenant, ctx.id, generation)
      snapshot = change_snapshot(ctx, head, generation)
      events = reset_events(head, snapshot, ctx.action)

      with {:ok, ref} <- immutable(ctx.principal.tenant, ctx.id, generation, "revisions", snapshot, ctx.opts),
           {:ok, head} <- append_events(head, events, ctx.opts),
           {:ok, head} <- retire_recording(head, ctx.opts) do
        next = changed_head(head, snapshot, ref)
        publish_result(write_head(ctx.principal.tenant, ctx.id, next, ctx.etag, ctx.opts), ctx, snapshot, ref)
      end
    end
  end

  defp retire_recording(head, opts) do
    case Map.get(head, "recording_series", []) do
      [] ->
        {:ok, head}

      series ->
        clock = Keyword.get(opts, :clock_ns, fn -> System.system_time(:nanosecond) end)
        timestamp = max(clock.(), String.to_integer(head["completed_at_ns"]) + 1)
        head = Map.put(head, "recording_fence_ns", Integer.to_string(timestamp))
        enqueue_recording(head, Recording.retirement(series, timestamp), opts)
    end
  end

  defp generation(_old, "create"), do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  defp generation(%{"state" => "deleted"}, "restore"), do: generation(nil, "create")
  defp generation(old, _), do: old["generation"]

  defp change_snapshot(ctx, head, generation) do
    class = Rule.classification(ctx.rule)

    %{
      "schema_version" => 1,
      "tenant" => ctx.principal.tenant,
      "id" => ctx.id,
      "generation" => generation,
      "parent" => head["revision"],
      "change_seq" => head["change_seq"] + 1,
      "rule" => ctx.rule,
      "notification_targets" => ctx.targets,
      "state" => rule_state(ctx.action, ctx.rule),
      "classification" => class,
      "change_classification" => Enum.uniq(head["classification"] ++ class),
      "actor" => %{"id" => ctx.principal.id, "type" => ctx.principal.type},
      "reason" => ctx.params["reason"],
      "operation_id" => ctx.params["operation_id"],
      "request_digest" => ctx.digest,
      "restored_from" => ctx.params["restored_from"],
      "publication_time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp rule_state("delete", _), do: "deleted"
  defp rule_state(_, %{"enabled" => true}), do: "active"
  defp rule_state(_, _), do: "disabled"

  defp reset_events(head, snapshot, action) do
    timestamp = System.system_time(:nanosecond) |> Integer.to_string()

    head["instances"]
    |> Enum.sort()
    |> Enum.map(fn {_key, instance} ->
      %{
        "type" => "resolved",
        "reason" => "rule_#{action}",
        "instance" => instance,
        "revision" => head["revision"],
        "classification" => head["classification"],
        "timestamp_ns" => timestamp,
        "actor" => snapshot["actor"]
      }
    end)
  end

  defp changed_head(head, snapshot, ref) do
    receipt = %{
      "operation_id" => snapshot["operation_id"],
      "request_digest" => snapshot["request_digest"],
      "revision" => ref
    }

    # Per-rule group diagnostics describe the previous revision's rules.
    head = Map.delete(head, "recording_rules")

    head =
      if snapshot["rule"]["kind"] == "promql_recording_group", do: Map.put(head, "recording_rules", []), else: head

    Map.merge(head, %{
      "generation" => snapshot["generation"],
      "revision" => ref,
      "state" => snapshot["state"],
      "classification" => snapshot["classification"],
      "change_seq" => snapshot["change_seq"],
      "instances" => %{},
      "health" => "unknown",
      "evaluation_revision" => nil,
      "operations" => Enum.take([receipt | head["operations"]], @receipt_limit),
      "notification_targets" => snapshot["notification_targets"]
    })
  end

  defp publish_result({:ok, _}, _ctx, snapshot, ref), do: {:ok, Map.put(snapshot, "revision", ref["digest"])}

  defp publish_result({:error, _}, ctx, _snapshot, _ref),
    do:
      recover(
        ctx.principal.tenant,
        ctx.id,
        ctx.params["expected_revision"],
        ctx.params["operation_id"],
        ctx.digest,
        ctx.opts
      )

  defp recover(tenant, id, expected, operation, digest, opts) do
    case load(tenant, id, opts) do
      {:ok, head, _} ->
        case find_receipt(head, operation) do
          %{"request_digest" => ^digest, "revision" => ref} -> result(tenant, id, ref, opts)
          receipt when is_map(receipt) -> {:error, :operation_reused}
          nil -> resolve_ancestry(tenant, id, head["revision"], expected, operation, digest, 128, opts)
        end

      _ ->
        {:error, :ambiguous_operation}
    end
  end

  defp resolve_ancestry(_tenant, _id, _ref, _expected, _operation, _digest, 0, _opts),
    do: {:error, :ambiguous_operation}

  defp resolve_ancestry(tenant, id, ref, expected, operation, digest, budget, opts) do
    case revision(tenant, id, ref, opts) do
      {:ok, snapshot} ->
        parent = snapshot["parent"]
        parent_digest = if parent, do: parent["digest"]

        case {parent_digest == expected, parent} do
          {true, _} -> unique_child(snapshot, ref, operation, digest)
          {false, nil} -> {:error, :conflict}
          {false, parent} -> resolve_ancestry(tenant, id, parent, expected, operation, digest, budget - 1, opts)
        end

      _ ->
        {:error, :ambiguous_operation}
    end
  end

  defp unique_child(%{"operation_id" => operation} = snapshot, ref, operation, request) do
    digest = if is_map(request), do: request_digest(request, snapshot["notification_targets"]), else: request

    if snapshot["request_digest"] == digest,
      do: {:ok, Map.put(snapshot, "revision", ref["digest"])},
      else: {:error, :operation_reused}
  end

  defp unique_child(_, _, _, _), do: {:error, :conflict}

  defp result(tenant, id, ref, opts) do
    with {:ok, snapshot} <- revision(tenant, id, ref, opts), do: {:ok, Map.put(snapshot, "revision", ref["digest"])}
  end

  defp authorize_old(_, nil, _), do: :ok

  defp authorize_old(principal, old, _) do
    classification =
      if Map.get(old, "recording_series", []) != [] or Map.get(old, "recording_queue", []) != [],
        do: Enum.uniq(["alert:record" | old["classification"]]),
        else: old["classification"]

    Principal.authorize(principal, "alert:rules:write", classification)
  end

  defp find_receipt(nil, _), do: nil
  defp find_receipt(head, id), do: Enum.find(head["operations"], &(&1["operation_id"] == id))

  defp existing(tenant, id, opts) do
    case load(tenant, id, opts) do
      {:error, :not_found} -> {:ok, nil, nil}
      other -> other
    end
  end

  defp empty(tenant, id, generation) do
    %{
      "schema_version" => 1,
      "tenant" => tenant,
      "id" => id,
      "generation" => generation,
      "revision" => nil,
      "state" => "disabled",
      "classification" => [],
      "change_seq" => 0,
      "completed_at_ns" => "-1",
      "instances" => %{},
      "health" => "unknown",
      "evaluation_revision" => nil,
      "event_seq" => 0,
      "history_floor" => 1,
      "tail" => [],
      "pages" => [],
      "operations" => [],
      "notification_targets" => [],
      "outboxes" => %{},
      "recording_queue" => [],
      "recording_series" => [],
      "recording_fence_ns" => "-1"
    }
  end

  defp walk(_tenant, _id, nil, _limit, acc, _opts), do: {:ok, %{changes: Enum.reverse(acc), next: nil}}
  defp walk(_tenant, _id, ref, 0, acc, _opts), do: {:ok, %{changes: Enum.reverse(acc), next: ref}}

  defp walk(tenant, id, ref, limit, acc, opts) do
    with {:ok, snapshot} <- revision(tenant, id, ref, opts) do
      walk(
        tenant,
        id,
        snapshot["parent"],
        limit - 1,
        [snapshot |> Map.put("revision", ref["digest"]) |> Map.put("_committed_ref", ref) | acc],
        opts
      )
    end
  end

  defp append_events(head, events, opts) do
    Enum.reduce_while(events, {:ok, head}, fn event, {:ok, head} ->
      seq = head["event_seq"] + 1

      event =
        Map.merge(event, %{
          "schema_version" => 1,
          "tenant" => head["tenant"],
          "id" => head["id"],
          "generation" => head["generation"],
          "sequence" => Integer.to_string(seq),
          "notification_targets" => Map.get(head, "notification_targets", [])
        })

      event =
        Map.put(
          event,
          "event_id",
          Canonical.hash([
            "alert-event-v1",
            head["tenant"],
            head["id"],
            head["generation"],
            Integer.to_string(seq),
            event["type"]
          ])
        )

      case immutable(head["tenant"], head["id"], head["generation"], "events", event, opts) do
        {:ok, ref} ->
          head = Map.merge(head, %{"event_seq" => seq, "tail" => head["tail"] ++ [%{"seq" => seq, "ref" => ref}]})

          finish_append(head, event, ref, opts)

        error ->
          {:halt, error}
      end
    end)
  end

  defp finish_append(head, event, ref, opts) do
    with {:ok, head} <- enqueue_notification(head, event, ref),
         {:ok, head} <- seal(head, opts),
         do: {:cont, {:ok, head}},
         else: (error -> {:halt, error})
  end

  defp enqueue_notification(head, event, ref) do
    if deliverable?(event) do
      Enum.reduce_while(event["notification_targets"], {:ok, head}, &enqueue_target(&1, &2, ref))
    else
      {:ok, head}
    end
  end

  defp deliverable?(%{"type" => type}) when type in ["firing", "retriggered"], do: true

  defp deliverable?(%{"type" => "resolved", "instance" => %{"status" => status}}),
    do: status in ["firing", "recovering"]

  defp deliverable?(_), do: false

  defp enqueue_target(target, {:ok, head}, ref) do
    boxes = Map.get(head, "outboxes", %{})
    box = Map.get(boxes, target["version"], %{"target" => target, "queue" => [], "claim" => nil})

    if length(box["queue"]) < 64 and (Map.has_key?(boxes, target["version"]) or map_size(boxes) < 16) do
      next = Map.put(box, "queue", box["queue"] ++ [ref])
      {:cont, {:ok, Map.put(head, "outboxes", Map.put(boxes, target["version"], next))}}
    else
      {:halt, {:error, :notification_backlog}}
    end
  end

  defp seal(%{"tail" => tail} = head, _opts) when length(tail) < @tail_limit, do: {:ok, head}

  defp seal(head, opts) do
    with {:ok, events} <- fetch_refs(head["tenant"], head["id"], head["tail"], opts),
         {:ok, ref} <-
           immutable(
             head["tenant"],
             head["id"],
             head["generation"],
             "history",
             %{"tenant" => head["tenant"], "id" => head["id"], "events" => events},
             opts
           ) do
      page = %{"first" => hd(head["tail"])["seq"], "last" => List.last(head["tail"])["seq"], "ref" => ref}
      pages = Enum.take(head["pages"] ++ [page], -@page_limit)
      {:ok, Map.merge(head, %{"tail" => [], "pages" => pages, "history_floor" => hd(pages)["first"]})}
    end
  end

  defp fetch_refs(tenant, id, refs, opts) do
    Enum.reduce_while(refs, {:ok, []}, fn item, {:ok, acc} ->
      case revision(tenant, id, item["ref"], opts) do
        {:ok, event} -> {:cont, {:ok, acc ++ [event]}}
        error -> {:halt, error}
      end
    end)
  end

  defp read_events(_tenant, _id, _pages, _tail, _after, 0, acc, _opts), do: {:ok, acc}

  defp read_events(tenant, id, [page | rest], tail, after_seq, limit, acc, opts) do
    with {:ok, object} <- revision(tenant, id, page["ref"], opts) do
      events = Enum.filter(object["events"], &(String.to_integer(&1["sequence"]) > after_seq)) |> Enum.take(limit)
      read_events(tenant, id, rest, tail, after_seq, limit - length(events), acc ++ events, opts)
    end
  end

  defp read_events(tenant, id, [], tail, after_seq, limit, acc, opts) do
    with {:ok, events} <- fetch_refs(tenant, id, Enum.filter(tail, &(&1["seq"] > after_seq)) |> Enum.take(limit), opts),
         do: {:ok, acc ++ events}
  end

  defp immutable(tenant, id, generation, kind, object, opts) do
    bytes = Canonical.encode(object)
    digest = Canonical.digest(bytes)
    key = base(tenant, id) <> "/g/#{generation}/#{kind}/#{digest}.json"
    ref = %{"key" => key, "digest" => digest, "bytes" => byte_size(bytes)}

    with true <- byte_size(bytes) <= @max_object_bytes,
         {:ok, store, config} <- backend(opts) do
      case store.put_if_none_match(config, key, bytes) do
        {:ok, _} ->
          {:ok, ref}

        _ ->
          recover_object(tenant, id, ref, opts)
      end
    else
      false -> {:error, :object_limit}
      error -> error
    end
  end

  defp write_head(tenant, id, head, etag, opts) do
    bytes = Canonical.encode(head)

    with true <- byte_size(bytes) <= @max_object_bytes,
         {:ok, store, config} <- backend(opts) do
      key = base(tenant, id) <> "/head.json"

      result =
        if etag, do: store.put_if_match(config, key, bytes, etag), else: store.put_if_none_match(config, key, bytes)

      case result do
        {:ok, _} ->
          {:ok, head}

        _ ->
          recover_head(tenant, id, head, opts)
      end
    else
      false -> {:error, :object_limit}
      error -> error
    end
  end

  defp recover_object(tenant, id, ref, opts) do
    case revision(tenant, id, ref, opts) do
      {:ok, _} -> {:ok, ref}
      _ -> {:error, :ambiguous_object_write}
    end
  end

  defp recover_head(tenant, id, head, opts) do
    case load(tenant, id, opts) do
      {:ok, ^head, _} -> {:ok, head}
      _ -> {:error, :ambiguous_head_write}
    end
  end

  @doc false
  def update_outbox(tenant, id, version, fun, opts \\ []) do
    with {:ok, head, etag} <- load(tenant, id, opts),
         box when is_map(box) <- Map.get(Map.get(head, "outboxes", %{}), version),
         {:ok, next_box} <- fun.(box) do
      boxes =
        if next_box["queue"] == [] and is_nil(next_box["claim"]),
          do: Map.delete(head["outboxes"], version),
          else: Map.put(head["outboxes"], version, next_box)

      next = Map.put(head, "outboxes", boxes)

      case write_head(tenant, id, next, etag, opts) do
        {:ok, _} -> {:ok, next_box}
        {:error, _} -> confirm_outbox(tenant, id, version, next_box, opts)
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp confirm_outbox(tenant, id, version, expected, opts) do
    with {:ok, head, _} <- load(tenant, id, opts) do
      current = head["outboxes"][version]
      removed = is_nil(current) and expected["queue"] == [] and is_nil(expected["claim"])
      if current == expected or removed, do: {:ok, expected}, else: {:error, :outbox_conflict}
    end
  end

  defp backend(opts) do
    env = Runtime.get_env(:pulse, Pulse.Alerting, [])
    store = Keyword.get(opts, :store, Keyword.get(env, :object_store, Pulse.ObjectStore))
    config = Keyword.get(opts, :store_config, Keyword.get(env, :store_config, Runtime.get_env(:pulse, S3)))
    if is_nil(config), do: {:error, :not_configured}, else: {:ok, store, Map.new(config)}
  end

  defp valid_head?(head, tenant, id) do
    Enum.all?([
      head["schema_version"] == 1,
      head["id"] == id,
      head["tenant"] == tenant,
      head["state"] in ["active", "disabled", "deleted"],
      is_map(head["revision"]),
      valid_generation?(head["generation"]),
      nonnegative?(head["change_seq"], 1),
      nonnegative?(head["event_seq"], 0),
      nonnegative?(head["history_floor"], 1),
      is_map(head["instances"]),
      is_list(head["classification"]),
      bounded_list?(head["pages"], @page_limit),
      bounded_list?(head["tail"], @tail_limit - 1),
      bounded_list?(head["operations"], @receipt_limit),
      timestamp?(head["completed_at_ns"]),
      recording_queue?(Map.get(head, "recording_queue", []), tenant, id),
      recording_series?(Map.get(head, "recording_series", [])),
      timestamp?(Map.get(head, "recording_fence_ns", "-1"))
    ])
  end

  defp recording_queue?(queue, tenant, id) when is_list(queue) and length(queue) <= 64,
    do: Enum.all?(queue, &recording_ref?(&1, tenant, id))

  defp recording_queue?(_, _, _), do: false

  defp recording_ref?(%{"inline" => object, "digest" => digest, "bytes" => bytes} = ref, _tenant, _id)
       when map_size(ref) == 3 and is_map(object) and is_binary(digest) and is_integer(bytes),
       do: Regex.match?(~r/\A[0-9a-f]{64}\z/, digest) and bytes in 1..@inline_limit

  defp recording_ref?(%{"key" => key, "digest" => digest, "bytes" => bytes}, tenant, id)
       when is_binary(key) and is_binary(digest) and is_integer(bytes) do
    String.starts_with?(key, base(tenant, id) <> "/g/") and Regex.match?(~r/\A[0-9a-f]{64}\z/, digest) and
      String.ends_with?(key, "/recordings/#{digest}.json") and bytes in 1..@max_object_bytes
  end

  defp recording_ref?(_, _, _), do: false

  defp recording_series?(series),
    do: bounded_list?(series, Recording.limits("promql_recording_group").samples) and Enum.all?(series, &Rule.labels?/1)

  defp valid_generation?(value), do: is_binary(value) and byte_size(value) == 32
  defp nonnegative?(value, minimum), do: is_integer(value) and value >= minimum
  defp bounded_list?(value, maximum), do: is_list(value) and length(value) <= maximum
  defp timestamp?(value), do: is_binary(value) and match?({_, ""}, Integer.parse(value))

  defp mutation_parameters(%{"operation_id" => op, "reason" => reason} = params)
       when is_binary(op) and byte_size(op) in 1..128 and is_binary(reason) and byte_size(reason) in 1..2048 do
    expected = params["expected_revision"]

    if is_nil(expected) or (is_binary(expected) and Regex.match?(~r/\A[0-9a-f]{64}\z/, expected)),
      do: :ok,
      else: {:error, :invalid_arguments}
  end

  defp mutation_parameters(_), do: {:error, :invalid_arguments}

  defp identifiers(tenant, id),
    do: if(Principal.valid_id?(tenant) and Principal.valid_id?(id), do: :ok, else: {:error, :invalid_id})

  defp base(tenant, id), do: "tenants/#{tenant}/alerting/v1/rules/#{id}"

  defp decode(bytes) when byte_size(bytes) <= @max_object_bytes do
    case Pulse.JSON.decode(bytes) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _ -> {:error, :integrity_error}
    end
  end

  defp decode(_), do: {:error, :object_limit}
end
