defmodule Pulse.Alerting do
  @moduledoc "Shared, capability-checked alert rule management and durable history service."
  alias Pulse.Alerting.{Cursor, Principal, Recording, Repository, Rule}

  def get(principal, id, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:read"),
         {:ok, head, _} <- Repository.load(principal.tenant, id, opts),
         :ok <- Principal.authorize(principal, "alert:read", head["classification"]),
         false <- head["state"] == "deleted",
         {:ok, snapshot} <- Repository.revision(principal.tenant, id, head["revision"], opts) do
      {:ok,
       %{"id" => id, "revision" => head["revision"]["digest"], "state" => head["state"], "rule" => snapshot["rule"]}}
    else
      true -> {:error, :not_found}
      error -> error
    end
  end

  def list(principal, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:read"),
         {:ok, ids} <- Repository.list(principal.tenant, opts) do
      Enum.reduce_while(ids, {:ok, []}, &list_rule(principal, &1, &2, opts))
    end
  end

  defp list_rule(principal, id, {:ok, acc}, opts) do
    case get(principal, id, opts) do
      {:ok, rule} -> {:cont, {:ok, [rule | acc]}}
      {:error, reason} when reason in [:not_found, :forbidden] -> {:cont, {:ok, acc}}
      error -> {:halt, error}
    end
  end

  defp public_parent(entry), do: Map.put(entry, "parent", parent_digest(entry["parent"]))
  defp parent_digest(nil), do: nil
  defp parent_digest(parent), do: parent["digest"]

  def create(principal, id, params, opts \\ []), do: change(principal, id, "create", params, opts)
  def update(principal, id, params, opts \\ []), do: change(principal, id, "update", params, opts)

  def delete(principal, id, params, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:rules:write"),
         {:ok, head, _} <- Repository.load(principal.tenant, id, opts),
         :ok <- Principal.authorize(principal, "alert:rules:write", head["classification"]),
         {:ok, current} <- Repository.revision(principal.tenant, id, head["revision"], opts),
         do: change(principal, id, "delete", Map.put(params, "rule", Map.put(current["rule"], "enabled", false)), opts)
  end

  def changes(principal, id, params \\ %{}, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:audit:read"),
         {:ok, ref} <- Cursor.open(params["cursor"], principal, id, opts),
         {:ok, page} <- Repository.history(principal.tenant, id, ref, Map.get(params, "limit", 20), opts),
         :ok <- authorize_snapshots(principal, page.changes) do
      entries =
        Enum.map(page.changes, fn snapshot ->
          snapshot
          |> Map.take(
            ~w(revision change_seq actor reason operation_id publication_time restored_from state generation parent)
          )
          |> Map.put("revision_cursor", Cursor.seal(principal, "revision:" <> id, snapshot["_committed_ref"], opts))
        end)

      # Parent storage paths stay server-side, even for ordinary authorized audit reads.
      entries = Enum.map(entries, &public_parent/1)

      cursor = if page.next, do: Cursor.seal(principal, id, page.next, opts)
      {:ok, %{"changes" => entries, "next_cursor" => cursor}}
    end
  end

  def historical(principal, id, value, opts \\ [])

  def historical(principal, id, %{"revision" => digest, "revision_cursor" => token}, opts) do
    with :ok <- Principal.authorize(principal, "alert:audit:read"),
         {:ok, %{"digest" => ^digest} = ref} <- Cursor.open(token, principal, "revision:" <> id, opts),
         {:ok, snapshot} <- Repository.revision(principal.tenant, id, ref, opts),
         :ok <- authorize_snapshots(principal, [snapshot]) do
      {:ok, snapshot |> Map.drop(["parent", "request_digest"]) |> Map.put("revision", digest)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_arguments}
    end
  end

  def historical(principal, id, %{"revision" => digest}, opts), do: historical(principal, id, digest, opts)

  def historical(principal, id, digest, opts) do
    with :ok <- Principal.authorize(principal, "alert:audit:read"),
         true <- is_binary(digest) and byte_size(digest) == 64,
         {:ok, snapshot} <- find_snapshot(principal.tenant, id, digest, nil, 4, opts),
         :ok <- authorize_snapshots(principal, [snapshot]) do
      {:ok, Map.drop(snapshot, ["parent", "request_digest", "_committed_ref"])}
    else
      false -> {:error, :invalid_arguments}
      error -> error
    end
  end

  def restore(principal, id, params, opts \\ []) do
    with {:ok, snapshot} <- historical(principal, id, Map.take(params, ["revision", "revision_cursor"]), opts) do
      # Re-enable is a separate explicit update. Restore never replays lifecycle or receipts.
      params =
        params
        |> Map.drop(["revision", "revision_cursor"])
        |> Map.put("restored_from", snapshot["revision"])
        |> Map.put("rule", Map.put(snapshot["rule"], "enabled", false))

      change(principal, id, "restore", params, opts)
    end
  end

  def state(principal, id, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:read"),
         {:ok, head, _} <- Repository.load(principal.tenant, id, opts),
         :ok <- Principal.authorize(principal, "alert:read", Recording.state_classification(head)) do
      notifications =
        Map.get(head, "outboxes", %{})
        |> Enum.map(fn {version, box} ->
          %{
            "target" => box["target"]["id"],
            "version" => version,
            "pending" => length(box["queue"]),
            "claim_expires_ns" => if(box["claim"], do: box["claim"]["expires_ns"])
          }
        end)

      {:ok,
       head
       |> Map.take(
         ~w(id generation state completed_at_ns evaluation_revision health instances recording_last recording_error recording_fence_ns recording_rules)
       )
       |> Map.put("recording_pending", length(Map.get(head, "recording_queue", [])))
       |> Map.put("notifications", notifications)}
    end
  end

  def events(principal, id, params \\ %{}, opts \\ []) do
    with :ok <- Principal.authorize(principal, "alert:read"),
         {:ok, position} <- Cursor.open(params["cursor"], principal, "events:" <> id, opts),
         {:ok, head, _} <- Repository.load(principal.tenant, id, opts),
         after_seq = if(position, do: position["after"], else: head["history_floor"] - 1),
         {:ok, events} <- Repository.events(principal.tenant, id, after_seq, Map.get(params, "limit", 50), opts) do
      next =
        if events == [], do: after_seq, else: events |> List.last() |> Map.fetch!("sequence") |> String.to_integer()

      allowed =
        Enum.filter(events, &(Principal.authorize(principal, "alert:read", Recording.event_classification(&1)) == :ok))

      {:ok, %{"events" => allowed, "next_cursor" => Cursor.seal(principal, "events:" <> id, %{"after" => next}, opts)}}
    end
  end

  defp change(principal, id, action, params, opts) do
    with :ok <- Principal.authorize(principal, "alert:rules:write"),
         true <-
           is_map(params) and
             Map.keys(params) --
               (~w(rule operation_id expected_revision reason) ++
                  if(action == "restore", do: ["restored_from"], else: [])) == [],
         {:ok, rule} <- Rule.validate(params["rule"]),
         true <- rule["kind"] != "grafana" or rule["original"]["uid"] == id do
      with {:ok, snapshot} <- Repository.change(principal, id, action, rule, params, opts),
           :ok <- Principal.authorize(principal, "alert:rules:write", snapshot["change_classification"]),
           do: {:ok, snapshot}
    else
      false -> {:error, :invalid_arguments}
      error -> error
    end
  end

  defp authorize_snapshots(principal, snapshots) do
    Enum.reduce_while(snapshots, :ok, fn snapshot, :ok ->
      case Principal.authorize(principal, "alert:audit:read", snapshot["change_classification"]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp find_snapshot(_tenant, _id, _digest, _ref, 0, _opts), do: {:error, :history_scan_limit}

  defp find_snapshot(tenant, id, digest, ref, budget, opts) do
    with {:ok, page} <- Repository.history(tenant, id, ref, 100, opts) do
      case Enum.find(page.changes, &(&1["revision"] == digest)) do
        nil when is_nil(page.next) -> {:error, :not_found}
        nil -> find_snapshot(tenant, id, digest, page.next, budget - 1, opts)
        snapshot -> {:ok, snapshot}
      end
    end
  end
end
