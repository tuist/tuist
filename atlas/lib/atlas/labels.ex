defmodule Atlas.Labels do
  @moduledoc """
  Owner-scoped label preparation and single-use browser-approved output.

  PostgreSQL owns jobs, approvals, relay leases and dispatch claims. A committed
  dispatch is never returned to the queue, even if Chrome vanishes before output.
  No worker retries physical operations. Browser reports are not hardware proof.
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
      act(operation, session, data, user, "relay")
    end)
  end

  def url(id), do: AtlasWeb.Endpoint.url() <> "/operations/labels/" <> id

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

    %{
      "id" => s.id,
      "expiresAt" => DateTime.to_unix(s.expires_at, :millisecond),
      "relay" => relay,
      "jobs" => Enum.map(jobs(s), &serialize(&1, s))
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

  defp act(:relay, s, data, _, _) do
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

    Repo.update!(Ecto.Changeset.change(s, relay: relay))
    %{"ok" => true}
  end

  defp act(:print, s, %{"jobId" => id}, user, interface) do
    job = job!(s, id)

    if job.state == "preview-only" do
      ensure(
        Enum.all?(jobs(s), &(&1.action != "print" or &1.state == "preview-only")),
        409,
        "One print attempt per session. Inspect existing output first."
      )

      pending(job, s, user, interface)
    else
      serialize(job, s)
    end
  end

  defp act(:cut, s, _, user, interface) do
    case Enum.find(jobs(s), &(&1.action == "cut")) do
      nil ->
        ensure(
          Enum.any?(jobs(s), &(&1.action == "print" and &1.state == "sdk-confirmed")),
          409,
          "A confirmed print attempt is required before requesting a separate cut."
        )

        job = Repo.insert!(%Job{session_id: s.id, action: "cut", data: %{"title" => "Cut existing label only"}})
        pending(job, s, user, interface)

      job ->
        serialize(job, s)
    end
  end

  # Only the authenticated owner in the CSRF-protected dashboard can approve.
  # Neither MCP nor bearer API exposes this transition.
  defp act(:approve, s, %{"jobId" => id}, user, "dashboard") do
    job = job!(s, id)

    ensure(
      job.state == "awaiting-approval" and job.data["approvalExpiresAt"] > now(),
      409,
      "Approval missing, consumed or expired."
    )

    ensure(connected?(s, job), 409, "Reconnect the exact printer and supply before approving.")
    ensure(job.action != "cut" or s.relay["cutReady"] == true, 409, "Cut-capable relay required.")
    updated = Repo.update!(Ecto.Changeset.change(job, state: "queued"))
    audit!(user, "dashboard", s, "approved", updated)
    serialize(updated, s)
  end

  defp act(:claim, s, %{"jobId" => id} = data, user, "relay") do
    job = job!(s, id)
    ensure(fresh?(s) and s.relay["clientId"] == data["clientId"], 409, "Only the active relay may dispatch.")

    ensure(
      job.state == "queued" and job.data["approvalExpiresAt"] > now() and connected?(s, job),
      409,
      "Job cannot be claimed. Never retry uncertain output."
    )

    ensure(job.action != "cut" or s.relay["cutReady"] == true, 409, "Cut-capable relay required.")

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

    updated =
      Repo.update!(
        Ecto.Changeset.change(job,
          state: if(data["success"] == true, do: "sdk-confirmed", else: "uncertain"),
          data: Map.put(job.data, "result", clean(data["message"]))
        )
      )

    audit!(user, "api", s, "result", updated)
    serialize(updated, s)
  end

  defp act(_, _, _, _, _), do: ensure(false, 400, "Invalid label operation.")

  defp pending(job, s, user, interface) do
    ensure(
      fresh?(s) and s.relay["connected"] == true and s.relay["model"] == "M211" and s.relay["name"] != "" and
        s.relay["supply"] != "",
      409,
      "Connect an M211 and report printer/supply before requesting approval."
    )

    ensure(valid_zones?(s.relay["zoneDimensions"]), 409, "Positive printable zone dimensions are required.")

    data =
      Map.merge(job.data, %{
        "printer" => s.relay["name"],
        "supply" => s.relay["supply"],
        "zoneDimensions" => s.relay["zoneDimensions"],
        "approvalExpiresAt" => now() + 600_000
      })

    updated = Repo.update!(Ecto.Changeset.change(job, state: "awaiting-approval", data: data))
    audit!(user, interface, s, "approval_requested", updated)
    serialize(updated, s)
  end

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
      "approvalUrl" => url(s.id) <> "/jobs/" <> j.id <> "/approval"
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

  defp audit!(user, interface, s, action, job \\ nil) do
    :ok =
      Audit.record(
        "label." <> action,
        %{
          target_type: "label_session",
          target_id: s.id,
          metadata: %{path: "/operations/labels/" <> s.id, job_id: job && job.id}
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
