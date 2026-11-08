defmodule TuistLabels.Store do
  use GenServer
  alias TuistLabels.Renderer
  @ttl 8 * 60 * 60 * 1000
  @stale 35_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def request(operation, server \\ __MODULE__), do: GenServer.call(server, operation, 120_000)
  def now, do: System.system_time(:millisecond)
  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  def config do
    dir = System.get_env("M211_STATE_DIR")
    dir = if dir in [nil, ""], do: Path.expand("~/.config/m211-bridge"), else: dir

    case System.get_env("M211_AUTHORIZATION") do
      value when value in [nil, ""] ->
        []

      path ->
        auth = path |> File.read!() |> Jason.decode!()

        unless is_binary(auth["id"]) and Regex.match?(~r/^[a-zA-Z0-9_-]{1,80}$/, auth["id"]) and
                 Enum.all?(
                   ~w(sessionId text printer supply),
                   &(is_binary(auth[&1]) and String.trim(auth[&1]) != "")
                 ) and
                 is_boolean(Map.get(auth, "allowCut", false)),
               do: raise("Invalid single-use authorization.")

        file = System.get_env("M211_SESSION")
        file = if file in [nil, ""], do: Path.join(dir, "session.json"), else: file
        session = file |> File.read!() |> Jason.decode!()

        unless session["id"] == auth["sessionId"] and is_number(session["expiresAt"]) and
                 session["expiresAt"] > now(),
               do: raise("Authorization must match the saved, unexpired CLI session.")

        File.mkdir_p!(dir)
        File.chmod!(dir, 0o700)

        [
          authorization: auth,
          session: session,
          journal: Path.join(dir, "dispatch-#{auth["id"]}.json")
        ]
    end
  end

  @impl true
  def init(opts) do
    session = opts[:session]

    sessions =
      if session,
        do: %{session["id"] => Map.merge(session, %{"jobs" => [], "relay" => nil})},
        else: %{}

    {:ok,
     %{
       sessions: sessions,
       authorization: opts[:authorization],
       journal: opts[:journal],
       creations: %{}
     }}
  end

  @impl true
  def handle_call(operation, _from, state) do
    try do
      {reply, updated, changed} = perform(operation, state)
      if changed, do: Phoenix.PubSub.broadcast(TuistLabels.PubSub, "labels:" <> changed, :refresh)
      {:reply, {:ok, reply}, updated}
    rescue
      _error in [File.Error, ErlangError, MatchError, Jason.DecodeError] ->
        # Keep all sessions and consumed dispatch markers on I/O failure. Never grant output.
        {:reply,
         {:error, 500,
          "Operation failed safely. No new dispatch granted; inspect status before continuing."},
         state}
    catch
      {:api, status, message} -> {:reply, {:error, status, message}, state}
    end
  end

  defp perform({:create, ip}, state) do
    sessions = Map.reject(state.sessions, fn {_, s} -> s["expiresAt"] <= now() end)
    creations = Map.reject(state.creations, fn {_, {at, _}} -> now() - at >= 60_000 end)
    {at, count} = Map.get(creations, ip, {now(), 0})
    ensure(count < 10 and map_size(sessions) < 50, 429, "Session limit reached. Try later.")

    session = %{
      "id" => token(),
      "controlToken" => token(),
      "relayToken" => token(),
      "expiresAt" => now() + @ttl,
      "jobs" => [],
      "relay" => nil
    }

    {Map.drop(session, ~w(jobs relay)),
     %{
       state
       | sessions: Map.put(sessions, session["id"], session),
         creations: Map.put(creations, ip, {at, count + 1})
     }, nil}
  end

  defp perform({operation, id, credential, data}, state) do
    session = state.sessions[id]

    ensure(
      session && session["expiresAt"] > now(),
      401,
      "Session missing or expired. Create a new session."
    )

    role =
      cond do
        credential == session["controlToken"] -> :control
        credential == session["relayToken"] -> :relay
        true -> nil
      end

    ensure(role, 401, "Session credential required.")
    {reply, updated} = act(operation, session, role, data, state)
    changed = if updated != session, do: id
    {reply, %{state | sessions: Map.put(state.sessions, id, updated)}, changed}
  end

  defp act(:status, s, _role, _, state) do
    relay =
      if s["relay"],
        do:
          Map.merge(s["relay"], %{
            "connected" => fresh?(s) and s["relay"]["connected"],
            "stale" => !fresh?(s)
          })

    allowed = permitted?(s, state)

    jobs = Enum.map(s["jobs"], &Map.drop(&1, ["png"]))

    {%{
       "id" => s["id"],
       "expiresAt" => s["expiresAt"],
       "relay" => relay,
       "jobs" => jobs,
       "printingEnabled" => allowed,
       "cutAuthorized" => allowed and state.authorization["allowCut"] == true,
       "printAuthorization" =>
         if(allowed, do: %{"text" => state.authorization["text"], "copies" => 1, "cut" => false})
     }, s}
  end

  defp act(:image, s, _, job_id, _) do
    job = Enum.find(s["jobs"], &(&1["id"] == job_id))
    ensure(job && job["png"], 404, "Label image not found.")
    {job["png"], s}
  end

  defp act(:submit, s, role, data, _) do
    require_role(role, :control)
    items = data["items"]
    w = Map.get(data, "widthMm", 50)
    h = Map.get(data, "heightMm", 12)

    ensure(
      is_list(items) and length(items) in 1..50 and length(items) + length(s["jobs"]) <= 100,
      400,
      "Submit 1–50 labels; at most 100 per session."
    )

    ensure(
      is_number(w) and w >= 10 and w <= 200 and is_number(h) and h >= 5 and h <= 20,
      400,
      "Preview size must be 10–200 mm × 5–20 mm."
    )

    jobs =
      Enum.map(items, fn item ->
        {title, png} = Renderer.render(item, w, h)

        %{
          "id" => token(),
          "title" => title,
          "widthMm" => w,
          "heightMm" => h,
          "png" => png,
          "state" => "preview-only"
        }
      end)

    ensure(
      Enum.reduce(s["jobs"] ++ jobs, 0, &(&2 + byte_size(Map.get(&1, "png", "")))) <= 16_000_000,
      413,
      "Session image limit reached (16 MB)."
    )

    {%{"queued" => length(jobs), "state" => "preview-only"},
     Map.update!(s, "jobs", &(&1 ++ jobs))}
  end

  defp act(:relay, s, role, data, _) do
    require_role(role, :relay)
    client = data["clientId"]

    ensure(
      is_binary(client) and Regex.match?(~r/^[\w-]{10,80}$/, client),
      400,
      "Relay client ID required."
    )

    ensure(
      !fresh?(s) or s["relay"]["clientId"] == client,
      409,
      "Another Chrome relay tab is active. Close it and wait 35 seconds."
    )

    status =
      Map.new(
        ~w(message model name supply dimensions printerStatus supplyWidth supplyHeight),
        &{&1, clean(data[&1])}
      )

    zones = data["zoneDimensions"]

    ensure(
      zones == nil or
        ((is_list(zones) or is_map(zones)) and byte_size(Jason.encode!(zones)) <= 4000),
      400,
      "Invalid printable zone dimensions."
    )

    status =
      Map.merge(status, %{
        "clientId" => client,
        "seenAt" => now(),
        "connected" => data["connected"] == true,
        "cutReady" => data["cutReady"] == true,
        "zoneDimensions" => zones
      })

    {%{"ok" => true}, Map.put(s, "relay", status)}
  end

  defp act(:print, s, role, data, state) do
    require_role(role, :control)
    ensure(permitted?(s, state), 403, "No print authorization for this session.")
    job = Enum.find(s["jobs"], &(&1["id"] == data["jobId"]))

    ensure(
      job && job["title"] == state.authorization["text"],
      403,
      "Only the explicitly authorized label may print."
    )

    if job["state"] != "preview-only" do
      {job_reply(job), s}
    else
      ensure(
        connected?(s, state),
        409,
        "Authorized printer and supply must be connected with fresh status."
      )

      ensure(
        Enum.all?(s["jobs"], &(&1["state"] == "preview-only")),
        409,
        "The single print authorization is already in use."
      )

      queued =
        Map.merge(job, %{
          "state" => "queued",
          "printer" => state.authorization["printer"],
          "supply" => state.authorization["supply"]
        })

      {job_reply(queued), replace_job(s, queued)}
    end
  end

  defp act(:cut, s, role, _, state) do
    require_role(role, :control)

    ensure(
      permitted?(s, state) and state.authorization["allowCut"] == true,
      403,
      "No single-use cut authorization for this session."
    )

    case Enum.find(s["jobs"], &(&1["action"] == "cut")) do
      nil ->
        printed =
          case File.read(state.journal) do
            {:ok, bytes} -> Jason.decode!(bytes)
            _ -> nil
          end

        ensure(
          printed && printed["sessionId"] == s["id"],
          409,
          "No print attempt for this authorization to cut."
        )

        ensure(
          connected?(s, state) and s["relay"]["cutReady"] == true,
          409,
          "Updated cut-capable relay must be connected to the authorized printer and supply."
        )

        job = %{
          "id" => token(),
          "title" => "Cut existing label only",
          "action" => "cut",
          "state" => "queued",
          "printer" => state.authorization["printer"],
          "supply" => state.authorization["supply"]
        }

        {job_reply(job), Map.update!(s, "jobs", &(&1 ++ [job]))}

      job ->
        {job_reply(job), s}
    end
  end

  defp act(operation, s, role, data, state) when operation in [:claim, :result] do
    require_role(role, :relay)
    job = Enum.find(s["jobs"], &(&1["id"] == data["jobId"]))
    ensure(job, 404, "Job not found.")

    updated =
      if operation == :claim do
        ensure(
          fresh?(s) and s["relay"]["clientId"] == data["clientId"],
          409,
          "Only the active relay may dispatch a job."
        )

        ensure(
          permitted?(s, state) and connected?(s, state) and job["state"] == "queued" and
            (job["action"] != "cut" or state.authorization["allowCut"] == true),
          409,
          "Job cannot be claimed. Never retry uncertain output."
        )

        journal = state.journal <> if(job["action"] == "cut", do: ".cut", else: "")
        # Durable, exclusive consumption BEFORE granting dispatch; never remove on failure.
        case File.open(journal, [:write, :exclusive, :binary]) do
          {:ok, file} ->
            try do
              :ok = File.chmod(journal, 0o600)

              :ok =
                IO.binwrite(
                  file,
                  Jason.encode!(%{
                    sessionId: s["id"],
                    jobId: job["id"],
                    title: job["title"],
                    at: now()
                  })
                )

              :ok = :file.sync(file)
            after
              File.close(file)
            end

          {:error, :eexist} ->
            throw(
              {:api, 409,
               "Single-use authorization already consumed; inspect the physical printer."}
            )

          {:error, _} ->
            throw({:api, 500, "Could not safely record dispatch. No command granted."})
        end

        Map.merge(job, %{"state" => "dispatched", "dispatchedBy" => data["clientId"]})
      else
        ensure(
          job["state"] == "dispatched" and job["dispatchedBy"] == data["clientId"],
          409,
          "No dispatched job belongs to this relay."
        )

        Map.merge(job, %{
          "state" => if(data["success"] == true, do: "sdk-confirmed", else: "uncertain"),
          "result" => clean(data["message"])
        })
      end

    {job_reply(updated), replace_job(s, updated)}
  end

  defp clean(value) when is_binary(value), do: String.slice(value, 0, 300)
  defp clean(value) when is_number(value), do: to_string(value)
  defp clean(_), do: ""

  defp permitted?(s, state),
    do: state.authorization != nil and state.authorization["sessionId"] == s["id"]

  defp fresh?(s), do: s["relay"] != nil and now() - s["relay"]["seenAt"] < @stale

  defp connected?(s, state),
    do:
      fresh?(s) and s["relay"]["connected"] == true and
        s["relay"]["name"] == state.authorization["printer"] and
        s["relay"]["supply"] == state.authorization["supply"]

  defp require_role(role, wanted),
    do: ensure(role == wanted, 403, "This session credential cannot perform that action.")

  defp ensure(value, status, message), do: if(!value, do: throw({:api, status, message}))

  defp replace_job(s, job),
    do:
      Map.update!(s, "jobs", &Enum.map(&1, fn j -> if j["id"] == job["id"], do: job, else: j end))

  defp job_reply(job), do: Map.take(job, ~w(state)) |> Map.put("jobId", job["id"])
end
