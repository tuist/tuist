defmodule Atlas.Labels do
  @moduledoc """
  Owner-scoped label preparation and batched output through the owner's Chrome relay.

  The agent queues batches for the connected relay directly or, optionally, after
  the owner approves the exact batch in the dashboard. PostgreSQL owns jobs,
  approvals, relay leases and dispatch claims. A committed dispatch is never
  returned to the queue, even if Chrome vanishes before output. Labels dispatch one
  at a time in batch order; uncertain output stops all queued output. No worker
  retries physical operations. Browser reports are not hardware proof.
  """
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Labels.Job
  alias Atlas.Labels.Renderer
  alias Atlas.Labels.Session
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  @ttl 8 * 60 * 60
  @stale 35_000
  @approval_ttl 600_000
  @start_window 600_000
  @per_label 60_000

  def create(user, interface) do
    transact(fn ->
      authorize!(user, :create, interface)
      # Serialize admission per owner, including across application replicas.
      Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

      ensure(
        Repo.aggregate(from(s in Session, where: s.owner_id == ^user.id and s.expires_at > ^DateTime.utc_now()), :count) <
          10,
        429,
        "Too many active label sessions."
      )

      token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      session =
        Repo.insert!(%Session{
          owner_id: user.id,
          relay_token_hash: hash(token),
          expires_at: DateTime.add(DateTime.utc_now(), @ttl)
        })

      audit!(user, interface, session, "created")

      %{
        "id" => session.id,
        "relayToken" => token,
        "expiresAt" => DateTime.to_unix(session.expires_at, :millisecond),
        "relayUrl" => url(session.id) <> "#token=" <> token
      }
    end)
  end

  def request(user, operation, id, data \\ %{}, interface \\ "api") do
    transact(fn ->
      authorize!(user, operation, interface)
      session = session!(id)
      ensure(session.owner_id == user.id, 404, "Label session not found.")
      expire!(session)
      act(operation, session, data, user, interface)
    end)
  end

  # This capability grants only transport/status access, never preparation or approval.
  def relay(operation, id, token, data \\ %{}) when operation in [:status, :image, :relay, :claim, :result] do
    transact(fn ->
      session = session!(id)

      ensure(
        is_binary(token) and byte_size(token) <= 100 and
          Plug.Crypto.secure_compare(session.relay_token_hash, hash(token)),
        401,
        "Invalid relay credential."
      )

      user = Users.get_user(session.owner_id)
      authorize!(user, operation, "relay")
      expire!(session)
      act(operation, session, data, user, "relay")
    end)
  end

  def url(id), do: AtlasWeb.Endpoint.url() <> "/operations/labels/" <> id
  def batch_url(id, batch), do: url(id) <> "/batches/" <> batch <> "/approval"

  defp session!(id) do
    ensure(match?({:ok, _}, Atlas.UUIDv7.cast(id)), 404, "Label session not found.")
    session = Repo.one(from s in Session, where: s.id == ^id, lock: "FOR UPDATE")
    ensure(session && DateTime.after?(session.expires_at, DateTime.utc_now()), 404, "Label session missing or expired.")
    session
  end

  defp authorize!(user, operation, interface) do
    ensure(interface in ~w(api mcp dashboard relay), 403, "Labels require a personal Atlas connection.")
    scope = if operation in [:status, :image], do: "assets:read", else: "assets:write"
    ensure(Users.has_scope?(user, scope) and !Atlas.Demo.enabled?(), 403, "Labels require #{scope}.")
  end

  defp act(:status, s, _, _, _) do
    relay =
      if s.relay,
        do: Map.merge(s.relay, %{"connected" => fresh?(s) and s.relay["connected"] == true, "stale" => !fresh?(s)})

    jobs = jobs(s)

    %{
      "id" => s.id,
      "expiresAt" => DateTime.to_unix(s.expires_at, :millisecond),
      "relay" => relay,
      "counts" => Enum.frequencies_by(jobs, & &1.state),
      "jobs" => Enum.map(jobs, &serialize(&1, s))
    }
  end

  defp act(:image, s, %{"jobId" => id}, _, _) do
    job = job!(s, id)
    ensure(is_binary(job.png), 404, "Label preview not found.")
    job.png
  end

  defp act(:submit, s, data, user, interface) do
    items = data["items"]
    w = data["widthMm"] || 50
    h = data["heightMm"] || 12
    current = jobs(s)

    ensure(
      is_list(items) and length(items) in 1..50 and length(items) + length(current) <= 100,
      400,
      "Submit 1–50 labels; at most 100 per session."
    )

    ensure(
      valid_size?(w, h),
      400,
      "Preview size must be 10–200 mm × 5–20 mm."
    )

    rendered = Enum.map(items, &Renderer.render(&1, w, h))

    size =
      Enum.reduce(current, 0, &(byte_size(&1.png || "") + &2)) +
        Enum.reduce(rendered, 0, fn {_, png}, total -> total + byte_size(png) end)

    ensure(size <= 16_000_000, 413, "Session image limit reached (16 MB).")

    Enum.each(rendered, fn {title, png} ->
      Repo.insert!(%Job{session_id: s.id, png: png, data: %{"title" => title, "widthMm" => w, "heightMm" => h}})
    end)

    audit!(user, interface, s, "submitted")
    %{"queued" => length(rendered), "state" => "preview-only"}
  end

  defp act(:relay, s, data, user, _) do
    client = data["clientId"]
    ensure(is_binary(client) and Regex.match?(~r/^[\w-]{10,80}$/, client), 400, "Relay client ID required.")

    ensure(
      !fresh?(s) or s.relay["clientId"] == client,
      409,
      "Another Chrome relay tab is active. Close it and wait 35 seconds."
    )

    zones = data["zoneDimensions"]

    ensure(
      zones == nil or ((is_list(zones) or is_map(zones)) and byte_size(Jason.encode!(zones)) <= 4000),
      400,
      "Invalid printable zone dimensions."
    )

    relay =
      Map.new(~w(message model name supply dimensions printerStatus supplyWidth supplyHeight), &{&1, clean(data[&1])})

    relay =
      Map.merge(relay, %{
        "clientId" => client,
        "seenAt" => now(),
        "connected" => data["connected"] == true,
        "cutReady" => data["cutReady"] == true,
        "zoneDimensions" => zones
      })

    if data["restarted"] == true or (is_map(s.relay) and s.relay["clientId"] != client), do: abandon!(s, user)
    Repo.update!(Ecto.Changeset.change(s, relay: relay))
    %{"ok" => true}
  end

  # The signed-in owner's own connection page gets a fresh relay capability when the
  # private link's fragment did not survive (sign-in round trips drop it). Rotating it
  # never takes over a relay tab that is still active.
  defp act(:relay_token, s, data, user, "dashboard") do
    ensure(
      !fresh?(s) or s.relay["clientId"] == data["clientId"],
      409,
      "Another Chrome relay tab is active. Close it and wait 35 seconds."
    )

    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    Repo.update!(Ecto.Changeset.change(s, relay_token_hash: hash(token)))
    audit!(user, "dashboard", s, "relay_token_issued")
    %{"relayToken" => token}
  end

  defp act(:print, s, data, user, interface) do
    ids = data["jobIds"]
    all = jobs(s)

    selected =
      if ids in [nil, []] do
        Enum.filter(all, &(&1.action == "print" and &1.state == "preview-only"))
      else
        ensure(is_list(ids) and length(ids) <= 100 and ids == Enum.uniq(ids), 400, "Pass 1–100 distinct job IDs.")
        Enum.map(ids, &job!(s, &1))
      end

    ensure(
      selected != [] and Enum.all?(selected, &(&1.action == "print" and &1.state == "preview-only")),
      409,
      "Choose preview-only labels. A label that was queued or output is never printed again; submit it again."
    )

    queue!(s, selected, %{"cut" => data["cut"] != false}, data["approval"] == true, user, interface)
  end

  defp act(:cut, s, data, user, interface) do
    job = Repo.insert!(%Job{session_id: s.id, action: "cut", data: %{"title" => "Cut only"}})
    queue!(s, [job], %{}, data["approval"] == true, user, interface)
  end

  # Only the authenticated owner in the CSRF-protected dashboard can approve.
  # Neither MCP nor bearer API exposes this transition. Approval is optional.
  defp act(:approve, s, %{"batchId" => batch}, user, "dashboard") do
    jobs = Enum.filter(jobs(s), &(&1.data["batchId"] == batch))

    ensure(
      jobs != [] and Enum.all?(jobs, &(&1.state == "awaiting-approval")),
      409,
      "Approval missing, consumed or expired."
    )

    ensure(Enum.all?(jobs, &connected?(s, &1)), 409, "Reconnect the exact printer and supply before approving.")
    ensure(!Enum.any?(jobs, &cuts?/1) or s.relay["cutReady"] == true, 409, "Cut-capable relay required.")
    claim_by = claim_by(length(jobs))

    updated =
      Enum.map(
        jobs,
        &Repo.update!(Ecto.Changeset.change(&1, state: "queued", data: Map.put(&1.data, "claimBy", claim_by)))
      )

    audit!(user, "dashboard", s, "approved", nil, batch_metadata(updated))
    batch_result(s, updated)
  end

  defp act(:claim, s, %{"jobId" => id} = data, user, "relay") do
    job = job!(s, id)
    all = jobs(s)
    ensure(fresh?(s) and s.relay["clientId"] == data["clientId"], 409, "Only the active relay may dispatch.")

    ensure(
      job.state == "queued" and valid?(job.data["claimBy"]) and connected?(s, job),
      409,
      "Job cannot be claimed. Never retry uncertain output."
    )

    ensure(!cuts?(job) or s.relay["cutReady"] == true, 409, "Cut-capable relay required.")
    ensure(!Enum.any?(all, &(&1.state == "dispatched")), 409, "Another operation is in flight.")

    # Labels print strictly in batch order, each only after every earlier one was confirmed.
    ensure(
      Enum.all?(all, fn other ->
        other.data["batchId"] != job.data["batchId"] or other.data["batchIndex"] >= job.data["batchIndex"] or
          other.state == "sdk-confirmed"
      end),
      409,
      "Earlier labels in this batch are not confirmed."
    )

    updated =
      Repo.update!(
        Ecto.Changeset.change(job,
          state: "dispatched",
          data: Map.merge(job.data, %{"dispatchedBy" => data["clientId"], "dispatchedAt" => now()})
        )
      )

    audit!(user, "api", s, "dispatched", updated)
    serialize(updated, s)
  end

  defp act(:result, s, %{"jobId" => id} = data, user, "relay") do
    job = job!(s, id)

    ensure(
      job.state == "dispatched" and job.data["dispatchedBy"] == data["clientId"],
      409,
      "No dispatched job belongs to this relay."
    )

    outcome =
      if job.action == "print",
        do: %{"printResult" => outcome(data["success"]), "cutResult" => cut_outcome(job, data["cutSuccess"])},
        else: %{"cutResult" => outcome(data["success"])}

    ok = data["success"] == true and outcome["cutResult"] in ["sdk-confirmed", "not-requested"]

    updated =
      Repo.update!(
        Ecto.Changeset.change(job,
          state: if(ok, do: "sdk-confirmed", else: "uncertain"),
          data: job.data |> Map.merge(outcome) |> Map.merge(%{"result" => clean(data["message"]), "resultAt" => now()})
        )
      )

    audit!(user, "api", s, "result", updated)
    if !ok, do: halt!(s, user, "Not printed: output stopped after uncertain #{job.data["title"]}.")
    serialize(updated, s)
  end

  defp act(_, _, _, _, _), do: ensure(false, 400, "Invalid label operation.")

  # Owner approval is optional: without it the agent's request queues output for the
  # connected relay directly. Either way the batch records the exact printer and supply.
  defp queue!(s, jobs, extra, approval?, user, interface) do
    ready!(s, extra["cut"] == true or Enum.any?(jobs, &(&1.action == "cut")))
    batch = Atlas.UUIDv7.generate()
    count = length(jobs)
    t = now()

    stamp =
      if approval?,
        do: %{"approvalExpiresAt" => t + @approval_ttl},
        else: %{"claimBy" => claim_by(count)}

    updated =
      jobs
      |> Enum.with_index()
      |> Enum.map(fn {job, index} ->
        data =
          job.data
          |> Map.drop(~w(note approvalExpiresAt claimBy))
          |> Map.merge(extra)
          |> Map.merge(stamp)
          |> Map.merge(%{
            "batchId" => batch,
            "batchIndex" => index,
            "batchSize" => count,
            "approval" => approval?,
            "queuedAt" => t,
            "printer" => s.relay["name"],
            "supply" => s.relay["supply"],
            "zoneDimensions" => s.relay["zoneDimensions"]
          })

        Repo.update!(
          Ecto.Changeset.change(job, state: if(approval?, do: "awaiting-approval", else: "queued"), data: data)
        )
      end)

    audit!(user, interface, s, if(approval?, do: "approval_requested", else: "queued"), nil, batch_metadata(updated))
    batch_result(s, updated)
  end

  defp ready!(s, cuts?) do
    ensure(
      fresh?(s) and s.relay["connected"] == true and s.relay["model"] == "M211" and s.relay["name"] != "" and
        s.relay["supply"] != "",
      409,
      "Connect an M211 and report printer/supply first."
    )

    ensure(valid_zones?(s.relay["zoneDimensions"]), 409, "Positive printable zone dimensions are required.")
    ensure(!cuts? or s.relay["cutReady"] == true, 409, "Cut-capable relay required.")
  end

  defp batch_result(s, [first | _] = jobs) do
    %{
      "batchId" => first.data["batchId"],
      "count" => length(jobs),
      "state" => first.state,
      "cut" => first.action == "cut" or first.data["cut"] == true,
      "approvalUrl" => if(first.state == "awaiting-approval", do: batch_url(s.id, first.data["batchId"])),
      "jobs" => Enum.map(jobs, &%{"id" => &1.id, "title" => &1.data["title"], "state" => &1.state})
    }
  end

  defp batch_metadata([first | _] = jobs), do: %{batch_id: first.data["batchId"], count: length(jobs)}

  # Unclaimed output that lost its approval window or start deadline returns to preview.
  # Nothing reached the printer, so this is not a retry; a new request is needed.
  defp expire!(s) do
    for job <- jobs(s),
        (job.state == "awaiting-approval" and !valid?(job.data["approvalExpiresAt"])) or
          (job.state == "queued" and !valid?(job.data["claimBy"])) do
      release!(job, "Not printed: #{if job.state == "queued", do: "start deadline", else: "approval"} expired.")
    end
  end

  # A restarted or replaced relay cannot finish what it dispatched: the outcome is unknown.
  defp abandon!(s, user) do
    abandoned =
      for job <- jobs(s), job.state == "dispatched" do
        updated =
          Repo.update!(
            Ecto.Changeset.change(job,
              state: "uncertain",
              data: Map.put(job.data, "result", "Relay restarted during output; outcome unknown. Inspect the printer.")
            )
          )

        audit!(user, "api", s, "result", updated)
      end

    if abandoned != [], do: halt!(s, user, "Not printed: output stopped after a relay restart.")
  end

  defp halt!(s, user, note) do
    halted = for job <- jobs(s), job.state == "queued", do: release!(job, note)
    if halted != [], do: audit!(user, "api", s, "halted", nil, %{count: length(halted)})
  end

  # A standalone cut that never reached the printer has nothing to preview; drop it.
  defp release!(%Job{action: "cut"} = job, _), do: Repo.delete!(job)

  defp release!(job, note) do
    Repo.update!(
      Ecto.Changeset.change(job,
        state: "preview-only",
        data: job.data |> Map.drop(~w(approvalExpiresAt claimBy)) |> Map.put("note", note)
      )
    )
  end

  defp cuts?(job), do: job.action == "cut" or job.data["cut"] == true
  defp claim_by(count), do: now() + @start_window + count * @per_label
  defp valid?(deadline), do: is_integer(deadline) and deadline > now()
  defp outcome(true), do: "sdk-confirmed"
  defp outcome(_), do: "uncertain"
  defp cut_outcome(%{data: %{"cut" => true}}, nil), do: "not-attempted"
  defp cut_outcome(%{data: %{"cut" => true}}, success), do: outcome(success)
  defp cut_outcome(_, _), do: "not-requested"

  defp jobs(s), do: Repo.all(from j in Job, where: j.session_id == ^s.id, order_by: [asc: j.inserted_at, asc: j.id])

  defp job!(s, id) do
    ensure(match?({:ok, _}, Atlas.UUIDv7.cast(id)), 404, "Label job not found.")
    job = Repo.get_by(Job, id: id, session_id: s.id)
    ensure(job, 404, "Label job not found.")
    job
  end

  defp serialize(j, s) do
    j.data
    |> Map.drop(~w(dispatchedBy))
    |> Map.merge(%{
      "id" => j.id,
      "jobId" => j.id,
      "state" => j.state,
      "action" => j.action,
      "approvalUrl" => if(j.state == "awaiting-approval", do: batch_url(s.id, j.data["batchId"]))
    })
  end

  defp connected?(s, j),
    do:
      fresh?(s) and s.relay["connected"] == true and s.relay["model"] == "M211" and s.relay["name"] == j.data["printer"] and
        s.relay["supply"] == j.data["supply"] and s.relay["zoneDimensions"] == j.data["zoneDimensions"]

  defp valid_zones?(zones) when is_list(zones) and zones != [] do
    Enum.all?(zones, fn
      %{"Width" => width, "Height" => height} -> positive?(width) and positive?(height)
      _ -> false
    end)
  end

  defp valid_zones?(_), do: false
  defp positive?(value) when is_number(value), do: value > 0

  defp positive?(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number > 0
      _ -> false
    end
  end

  defp positive?(_), do: false

  defp valid_size?(width, height),
    do: is_number(width) and width >= 10 and width <= 200 and is_number(height) and height >= 5 and height <= 20

  defp fresh?(s), do: is_map(s.relay) and now() - s.relay["seenAt"] < @stale
  defp now, do: System.system_time(:millisecond)
  defp hash(token), do: :crypto.hash(:sha256, token)
  defp clean(v) when is_binary(v), do: String.slice(v, 0, 300)
  defp clean(v) when is_number(v), do: to_string(v)
  defp clean(_), do: ""

  defp audit!(user, interface, s, action, job \\ nil, metadata \\ %{}) do
    :ok =
      Audit.record(
        "label." <> action,
        %{
          target_type: "label_session",
          target_id: s.id,
          metadata: Map.merge(%{path: "/operations/labels/" <> s.id, job_id: job && job.id}, metadata)
        },
        actor: user,
        interface: interface
      )
  end

  defp transact(fun) do
    Repo.transaction(fun)
  catch
    {:api, status, message} -> {:error, status, message}
  end

  defp ensure(value, status, message), do: if(!value, do: throw({:api, status, message}))
end
