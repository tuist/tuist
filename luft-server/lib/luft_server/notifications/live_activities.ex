defmodule LuftServer.Notifications.LiveActivities do
  @moduledoc """
  Luft's aggregate Live Activity: one ActivityKit activity per signed-in
  app that shows the user's working threads on the Lock Screen and in the
  Dynamic Island.

  The server decides what the activity shows. `content/2` maps the user's
  threads to a small versioned document (the activity's `content-state`) built
  from a fixed set of parts: a summary and up to three threads, each with a
  headline, a detail line, a phase with its SF Symbol and tint, progress (a timer
  the device counts from `started_at`, or a step count), a trail of its recent
  phases, a link and, while it works, a link that opens Luft's snooze choices
  for it. Snoozed threads are left out, so
  snoozing the last working one ends the activity. The widget only draws it,
  so new phases and copy ship from the server without an app release. Raw
  state never leaves the server: tool calls become phases (`Read`, `Glob`,
  `Grep` and `Ls` are Exploring, `Edit` and `Write` Editing, `Bash` Running
  commands, or Building and Testing while a Once run in its command reports
  progress, shown as the `done` of `total` planned targets its timer
  carries), and their arguments are never read.
  Headlines are the thread title an agent gave it (`Delegation.thread_title/1`),
  which can appear on the Lock Screen.

  Registrations (`LuftServer.Notifications.LiveActivity`) are keyed by the app's UUID for the
  activity, bound to the user and the Luft sign-in that registered it, and
  delivered to only while that sign-in is active. They last eight hours, as
  ActivityKit activities do. Retired rows are tombstones whose ID can never be
  registered again; a new local activity retires the previous one of the same
  sign-in.

  Every thread change wakes `Workers.LiveActivityWorker` for the owner's live
  registrations, coalesced to one pending job each. The worker recomputes the
  document from committed state, pushes it when it changed, and reschedules
  itself a minute later while threads are working, which renews the activity's
  stale date and repairs a lost wake. A push that changes what the activity
  shows of the threads' phases (a thread starting, moving from exploring to
  editing, finishing) goes at priority 10, so the Lock Screen and Dynamic
  Island follow the work as it happens; the app declares
  `NSSupportsLiveActivitiesFrequentUpdates` for the larger budget. Step counts
  and heartbeats go at priority 5, which iOS does not ration. A thread the last
  push showed working is shown finished once. When nothing is working the push
  ends the activity, leaving finished threads on the Lock Screen for a few
  minutes, and retires the registration.

  The app also registers its push-to-start token (`LuftServer.Notifications.LiveActivityStarter`,
  one per sign-in). When one of the user's threads starts working and that
  sign-in has no live registration, `Workers.LiveActivityStartWorker` creates a
  pending registration and starts the activity with it on the device, so the
  activity appears for threads started anywhere, without opening the app. The
  app then registers the started activity's update token under that ID within
  ten minutes; when it doesn't, the sign-in isn't started again for an hour,
  so a device that can't register doesn't collect cards that never update.
  A push-to-start token goes when the app unregisters it, another sign-in
  presents it, the server finds its sign-in ended or APNs rejects it, or no
  app registered it for 60 days.
  """

  import Ecto.Query

  alias LuftServer.Config
  alias LuftServer.Notifications.Delegation
  alias LuftServer.Notifications.Delegation.Actor, as: User
  alias LuftServer.Notifications.LiveActivity
  alias LuftServer.Notifications.LiveActivityStarter
  alias LuftServer.Notifications.LiveActivityStartWorker
  alias LuftServer.Notifications.LiveActivityWorker
  alias LuftServer.Notifications.Transport
  alias LuftServer.Repo
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolCall

  require Logger

  @version 1
  @lifetime_seconds 8 * 60 * 60
  @stale_seconds 2 * 60
  @heartbeat_seconds 60
  @linger_seconds 15 * 60
  # How long a pushed start waits for the app to register the activity's update
  # token before the sign-in can be started again.
  @pending_seconds 10 * 60
  # How long a sign-in whose device never registered a started activity waits
  # before the server starts another.
  @start_backoff_seconds 60 * 60
  # Apps register their push-to-start token on every launch; one not seen for
  # this long belongs to an app that's gone.
  @starter_stale_days 60
  @max_live_per_user 10
  @max_threads 3
  @max_title_length 80
  @max_trail 4
  @tombstone_retention_days 180
  @prune_batch_size 1000
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @profile_id ~r/\A[A-Za-z0-9_-]{1,128}\z/
  @token ~r/\A(?:[0-9a-fA-F]{2}){16,256}\z/

  @working ["queued", "running", "compacting", "shipping"]

  # Phase => {label, SF Symbol, tint}. Tints name the widget's fixed palette.
  @phases %{
    "waiting" => {"Waiting", "clock", "gray"},
    "thinking" => {"Thinking", "sparkles", "gray"},
    "exploring" => {"Exploring", "magnifyingglass", "blue"},
    "editing" => {"Editing", "pencil", "purple"},
    "running" => {"Running commands", "terminal", "orange"},
    "building" => {"Building", "hammer", "orange"},
    "testing" => {"Testing", "checklist", "teal"},
    "working" => {"Using tools", "wrench.and.screwdriver", "blue"},
    "shipping" => {"Shipping", "paperplane", "teal"},
    "needs_you" => {"Needs you", "bell.badge", "yellow"},
    "done" => {"Done", "checkmark.circle", "green"},
    "failed" => {"Failed", "xmark.circle", "red"}
  }

  @finished ["needs_you", "done", "failed"]

  def version, do: @version
  def prune_batch_size, do: @prune_batch_size

  @doc """
  Registers or refreshes Live Activity `id` for `user` under the Luft `session`
  (the exact local session UUID). `params` has `"token"`, the activity's hex
  ActivityKit push token, and `"environment"`, `sandbox` or `production`.

  Returns `{:ok, registration}`, or `{:error, reason}` where reason is
  `:invalid`, `:retired` (the app must use a new UUID) or `:conflict` (another
  user's registration).
  """
  def register(%User{} = user, %{app: "luft", oauth_grant_id: grant_id}, id, params) do
    with {:ok, id} <- validate_id(id),
         {:ok, token, environment} <- validate_params(params),
         :ok <- exact_session(user, grant_id) do
      hash = LiveActivity.token_hash(token)

      result =
        locked(id, user, fn
          %LiveActivity{retired_at: %DateTime{}} ->
            {:error, :retired}

          # A pending registration the server started gets the activity's full
          # lifetime, unless the device registered it too late: the server may
          # have started another since.
          %LiveActivity{user_id: user_id, oauth_grant_id: ^grant_id, token: nil} = pending
          when user_id == user.id ->
            if DateTime.after?(pending.expires_at, now()) do
              save(pending, user, grant_id, token, environment, hash, %{
                expires_at: DateTime.shift(now(), second: @lifetime_seconds)
              })
            else
              {:error, :retired}
            end

          %LiveActivity{user_id: user_id, oauth_grant_id: ^grant_id} = existing
          when user_id == user.id ->
            save(existing, user, grant_id, token, environment, hash)

          %LiveActivity{} ->
            {:error, :conflict}

          nil ->
            # One activity per sign-in: a new local activity replaces the old one.
            LiveActivity
            |> where(
              [a],
              a.user_id == ^user.id and a.oauth_grant_id == ^grant_id and is_nil(a.retired_at)
            )
            |> Repo.update_all(set: retired_fields("replaced"))

            save(
              %LiveActivity{id: id, expires_at: DateTime.shift(now(), second: @lifetime_seconds)},
              user,
              grant_id,
              token,
              environment,
              hash
            )
        end)

      with {:ok, registration} <- result do
        wake(registration.id)
        {:ok, registration}
      end
    end
  end

  def register(_user, _session, _id, _params), do: {:error, :invalid}

  @doc """
  Retires `id` when it belongs to `user`. An unknown ID becomes a tombstone, so a
  registration that arrives after it is rejected. Always `:ok` for a valid ID.
  The app ends the activity itself.
  """
  def unregister(%User{} = user, id) do
    with {:ok, id} <- validate_id(id) do
      {:ok, :ok} =
        locked(id, nil, fn
          nil ->
            Repo.insert!(
              struct(LiveActivity, [id: id, expires_at: now()] ++ retired_fields("unregistered"))
            )

            :ok

          %LiveActivity{retired_at: nil, user_id: user_id} = registration
          when user_id == user.id ->
            retire!(registration, "unregistered")
            :ok

          %LiveActivity{} ->
            :ok
        end)

      :ok
    end
  end

  @doc """
  Saves the ActivityKit push-to-start `"token"` of `user`'s Luft `session`,
  with its `"environment"` and the app's `"profile_id"` for the sign-in. One per
  sign-in and per token: a profile switch on the same device moves the token.
  Returns `:ok` or `{:error, :invalid}`.
  """
  def register_starter(%User{} = user, %{app: "luft", oauth_grant_id: grant_id}, params) do
    with {:ok, token, environment} <- validate_params(params),
         profile_id when is_binary(profile_id) <- params["profile_id"],
         true <- Regex.match?(@profile_id, profile_id),
         :ok <- exact_session(user, grant_id) do
      hash = LiveActivityStarter.token_hash(token)

      {:ok, :ok} =
        Repo.transaction(fn ->
          # Serializes sign-ins presenting the same token, which share its unique index.
          advisory_lock!("thread_live_activity_starter:" <> Base.encode16(hash))

          LiveActivityStarter
          |> where([s], s.token_hash == ^hash and s.oauth_grant_id != ^grant_id)
          |> Repo.delete_all()

          Repo.insert!(
            %LiveActivityStarter{
              user_id: user.id,
              oauth_grant_id: grant_id,
              profile_id: profile_id,
              environment: environment,
              token: token,
              token_hash: hash
            },
            on_conflict:
              {:replace, [:user_id, :profile_id, :environment, :token, :token_hash, :updated_at]},
            conflict_target: :oauth_grant_id
          )

          :ok
        end)

      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  def register_starter(_user, _session, _params), do: {:error, :invalid}

  @doc "Forgets the push-to-start token of `user`'s Luft `session`, such as before signing out."
  def unregister_starter(%User{} = user, %{oauth_grant_id: grant_id}) do
    LiveActivityStarter
    |> where([s], s.user_id == ^user.id and s.oauth_grant_id == ^grant_id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Wakes the live registrations of `user_id` after one of their threads changed,
  and the push-to-start tokens of their sign-ins without one. Called in the
  transaction that changes the thread, so the wake commits with it.
  """
  def thread_changed(user_id) do
    if is_integer(user_id) do
      LiveActivity
      |> where([a], a.user_id == ^user_id and is_nil(a.retired_at))
      |> select([a], a.id)
      |> Repo.all()
      |> Enum.each(&wake/1)

      if working?(user_id) do
        now = now()

        # `user_id` first, so the query uses its index rather than scanning tombstones.
        live =
          from(a in LiveActivity,
            where:
              a.user_id == parent_as(:starter).user_id and
                a.oauth_grant_id == parent_as(:starter).oauth_grant_id and
                is_nil(a.retired_at) and a.expires_at > ^now
          )

        from(s in LiveActivityStarter,
          as: :starter,
          where: s.user_id == ^user_id and not exists(live),
          select: s.id
        )
        |> Repo.all()
        |> Enum.each(&wake_starter/1)
      end
    end

    :ok
  end

  defp working?(user_id) do
    Repo.exists?(
      from(t in Thread,
        where: t.owner_id == ^user_id and t.status == :active and t.agent_status in @working
      )
    )
  end

  defp wake_starter(id) do
    {:ok, _job} =
      %{"starter_id" => id}
      |> LiveActivityStartWorker.new(schedule_in: 1, replace: [scheduled: [:scheduled_at]])
      |> Oban.insert()

    :ok
  end

  @doc """
  Starts the activity on the device of push-to-start token `id` when its user
  has threads working and its sign-in has no live registration: creates a
  pending registration and pushes the activity's attributes, naming it, with
  its first document. Returns `:ok`, `{:retry, reason}` or `{:cancel, reason}`.
  """
  def start(id) do
    fn ->
      with %LiveActivityStarter{} = starter <- Repo.get(LiveActivityStarter, id),
           # The same lock `register/4` takes, so a local start and a pushed one don't race.
           _ = advisory_lock!("thread_live_activity_user:#{starter.user_id}"),
           :ok <- check_starter(starter),
           %User{} = user <- Delegation.actor(starter.oauth_grant_id, starter.user_id),
           server_url = Config.public_url(),
           {document, [_ | _] = working_ids} <- content(user, [], server_url) do
        push_start(starter, document, working_ids, server_url)
      else
        _ -> :ok
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, result} -> result
      {:error, retry} -> retry
    end
  end

  defp check_starter(starter) do
    now = now()

    cond do
      not Delegation.active?(starter.oauth_grant_id, starter.user_id) ->
        Repo.delete!(starter)
        {:retired, "session_ended"}

      Repo.exists?(
        from(a in LiveActivity,
          where:
            a.user_id == ^starter.user_id and a.oauth_grant_id == ^starter.oauth_grant_id and
              is_nil(a.retired_at) and
                a.expires_at > ^now
        )
      ) ->
        {:retired, "live"}

      unregistered_start?(starter, now) ->
        {:retired, "backing_off"}

      true ->
        :ok
    end
  end

  # The device never registered the last activity the server started, such as
  # when iOS didn't wake the app: starting another would only add a card that
  # never updates, so the sign-in waits before the next try.
  defp unregistered_start?(%LiveActivityStarter{last_start_id: nil}, _now), do: false

  defp unregistered_start?(starter, now) do
    DateTime.diff(now, starter.last_started_at) < @start_backoff_seconds and
      Repo.exists?(
        from(a in LiveActivity,
          where:
            a.id == ^starter.last_start_id and is_nil(a.token) and
              (is_nil(a.retired_at) or a.retired_reason == "expired")
        )
      )
  end

  defp push_start(starter, document, working_ids, server_url) do
    now = now()
    timestamp = DateTime.to_unix(now)
    id = Ecto.UUID.generate()

    starter |> Ecto.Changeset.change(last_start_id: id, last_started_at: now) |> Repo.update!()

    pending =
      Repo.insert!(
        struct(
          LiveActivity,
          Map.merge(digests(document), %{
            id: id,
            user_id: starter.user_id,
            oauth_grant_id: starter.oauth_grant_id,
            environment: starter.environment,
            expires_at: DateTime.shift(now, second: @pending_seconds),
            last_sent_at: now,
            working_thread_ids: working_ids
          })
        )
      )

    aps = %{
      "timestamp" => timestamp,
      "event" => "start",
      "content-state" => document,
      "stale-date" => timestamp + @stale_seconds,
      "attributes-type" => "LuftActivityAttributes",
      "attributes" => %{
        "registrationID" => id,
        "profileID" => starter.profile_id,
        "server" => server_url
      },
      # iOS 18 and later hand the app the activity's update token only when asked.
      "input-push-token" => 1,
      "alert" => %{"title" => document["summary"]["headline"], "body" => document["fallback"]}
    }

    starter.oauth_grant_id
    |> Transport.deliver(starter.token, starter.environment, %{"aps" => aps},
      push_type: "liveactivity",
      priority: 10,
      expiration: timestamp + @stale_seconds
    )
    |> case do
      :ok ->
        :ok

      {:error, :invalid_token} ->
        retire!(pending, "invalid_token")
        Repo.delete!(starter)
        :ok

      {:error, {:retry, reason}} ->
        Repo.rollback({:retry, reason})

      {:error, {:rejected, reason}} ->
        Logger.warning(
          "Live Activity start rejected for #{starter.id} (#{starter.environment}): #{reason}"
        )

        retire!(pending, "rejected")
        {:cancel, reason}
    end
  end

  # A pending heartbeat is pulled forward to a second from now, so bursts of
  # changes coalesce into one push without waiting for the heartbeat.
  defp wake(id) do
    {:ok, _job} =
      %{"registration_id" => id}
      |> LiveActivityWorker.new(schedule_in: 1, replace: [scheduled: [:scheduled_at]])
      |> Oban.insert()

    :ok
  end

  @doc false
  def schedule_heartbeat(id) do
    {:ok, _job} =
      %{"registration_id" => id}
      |> LiveActivityWorker.new(schedule_in: @heartbeat_seconds)
      |> Oban.insert()

    :ok
  end

  @doc """
  Pushes registration `id` its current document. Returns `:continue` while
  threads are working (the worker schedules a heartbeat), `:done` once the
  registration is retired or gone, `{:snooze, seconds}`, `{:retry, reason}` or
  `{:cancel, reason}`.
  """
  def deliver(id) do
    {:ok, result} =
      Repo.transaction(fn ->
        case Repo.one(from a in LiveActivity, where: a.id == ^id, lock: "FOR UPDATE") do
          %LiveActivity{retired_at: nil, token: token} = registration when is_binary(token) ->
            push(registration)

          _ ->
            :done
        end
      end)

    result
  end

  defp push(%LiveActivity{} = registration) do
    now = now()

    with :ok <- check_live(registration, now),
         %User{} = user <- Delegation.actor(registration.oauth_grant_id, registration.user_id) do
      server_url = Config.public_url()
      {document, working_ids} = content(user, registration.working_thread_ids, server_url)
      event = if working_ids == [], do: "end", else: "update"
      digests = digests(document)
      since = registration.last_sent_at && DateTime.diff(now, registration.last_sent_at)

      cond do
        event == "update" and digests.last_digest == registration.last_digest and
            since < @heartbeat_seconds ->
          :continue

        # APNs orders updates by their second-precision timestamp.
        since == 0 ->
          {:snooze, 1}

        true ->
          send!(registration, document, working_ids, event, digests, now)
      end
    else
      {:retired, reason} ->
        retire!(registration, reason)
        :done

      nil ->
        retire!(registration, "session_ended")
        :done
    end
  end

  defp check_live(registration, now) do
    cond do
      DateTime.compare(registration.expires_at, now) != :gt ->
        {:retired, "expired"}

      not Delegation.active?(registration.oauth_grant_id, registration.user_id) ->
        {:retired, "session_ended"}

      true ->
        :ok
    end
  end

  # A digest of the whole document, which decides whether to push, and one of
  # only the phases it shows, which decides how urgently.
  defp digests(document) do
    phases = [
      document["summary"]["headline"]
      | Enum.map(document["threads"], &[&1["id"], settled_phase(&1)])
    ]

    %{
      last_digest: :crypto.hash(:sha256, JSON.encode!(document)),
      last_phase_digest: :crypto.hash(:sha256, JSON.encode!(phases))
    }
  end

  # A running thread thinks between every two tool calls; that pause isn't
  # news, so it counts as the phase before it. The document only carries the
  # trail's tints, so phases compare by tint (exploring and using tools share
  # one): a thinking thread's is the trail's second-to-last, as the trail ends
  # with the current phase's.
  defp settled_phase(%{"phase" => "thinking", "trail" => [_, _ | _] = trail}),
    do: Enum.at(trail, -2)

  defp settled_phase(%{"tint" => tint}), do: tint

  # Phase changes and the end are news; step counts and heartbeats aren't.
  defp priority("end", _digests, _registration), do: 10

  defp priority(_event, %{last_phase_digest: digest}, %LiveActivity{last_phase_digest: digest}),
    do: 5

  defp priority(_event, _digests, _registration), do: 10

  defp send!(registration, document, working_ids, event, digests, now) do
    timestamp = DateTime.to_unix(now)
    expires_at = DateTime.to_unix(registration.expires_at)
    stale_at = min(timestamp + @stale_seconds, expires_at)
    finished? = Enum.any?(document["threads"], &(&1["phase"] in @finished))

    aps =
      %{
        "timestamp" => timestamp,
        "event" => event,
        "content-state" => document,
        "stale-date" => stale_at
      }

    aps =
      if event == "end",
        do:
          Map.put(
            aps,
            "dismissal-date",
            if(finished?, do: timestamp + @linger_seconds, else: timestamp)
          ),
        else: aps

    registration.oauth_grant_id
    |> Transport.deliver(registration.token, registration.environment, %{"aps" => aps},
      push_type: "liveactivity",
      priority: priority(event, digests, registration),
      expiration: stale_at,
      collapse_id: registration.id
    )
    |> case do
      :ok when event == "end" ->
        retire!(registration, "ended")
        :done

      :ok ->
        registration
        |> Ecto.Changeset.change(
          Map.merge(digests, %{last_sent_at: now, working_thread_ids: working_ids})
        )
        |> Repo.update!()

        :continue

      {:error, :invalid_token} ->
        retire!(registration, "invalid_token")
        :done

      {:error, {:retry, reason}} ->
        {:retry, reason}

      {:error, {:rejected, reason}} ->
        Logger.warning(
          "Live Activity push rejected for #{registration.id} (#{registration.environment}): #{reason}"
        )

        {:cancel, reason}
    end
  end

  @doc """
  The document `user`'s activity shows, and the IDs of the threads it shows
  working. `previously_working` are the threads the last push showed working:
  those that finished since are shown finished, once.
  """
  def content(%User{} = user, previously_working \\ [], server_url \\ Config.public_url()) do
    threads =
      Thread
      |> where([t], t.owner_id == ^user.id and t.status == :active)
      |> where([t], t.agent_status in @working or t.id in ^previously_working)
      # A snoozed thread is out of the owner's way, here too.
      |> where(
        [t],
        not t.snoozed_until_needed and (is_nil(t.snoozed_until) or t.snoozed_until <= ^now())
      )
      |> Repo.all()
      |> readable(user)

    runs = latest_runs(Enum.map(threads, & &1.id))
    calls = runs |> Map.values() |> Enum.map(& &1.id) |> tool_calls()

    rows =
      threads
      |> Enum.map(fn thread ->
        run = Map.get(runs, thread.id)
        row(thread, run, if(run, do: Map.get(calls, run.id, []), else: []))
      end)
      |> Enum.sort_by(&{rank(&1.phase), &1.started_at, &1.thread.id})

    working = Enum.reject(rows, &(&1.phase in @finished))
    top = List.first(rows)
    count = length(working)

    summary =
      if top do
        {label, symbol, tint} = Map.fetch!(@phases, top.phase)

        headline =
          if count == 0, do: "All threads finished", else: "#{count} #{noun(count)} working"

        %{"headline" => headline, "phase" => label, "symbol" => symbol, "tint" => tint}
      else
        {label, symbol, tint} = Map.fetch!(@phases, "done")

        %{
          "headline" => "All threads finished",
          "phase" => label,
          "symbol" => symbol,
          "tint" => tint
        }
      end

    shown = Enum.take(rows, @max_threads)

    document = %{
      "v" => @version,
      "summary" => summary,
      "threads" => Enum.map(shown, &thread_document(&1, server_url)),
      "fallback" => fallback(summary, top)
    }

    {document, Enum.map(working, & &1.thread.id)}
  end

  defp readable(threads, user) do
    # Share only request-local decisions for the same original delegation and
    # account; never turn a recipient's other sign-in into an owner capability.
    key = &{&1.owner_id, &1.owner_session_id, &1.account_id, &1.account_handle}
    access = threads |> Enum.uniq_by(key) |> Map.new(&{key.(&1), Delegation.readable?(&1, user)})
    Enum.filter(threads, &Map.fetch!(access, key.(&1)))
  end

  defp latest_runs([]), do: %{}

  defp latest_runs(thread_ids) do
    Run
    |> where([r], r.thread_id in ^thread_ids)
    |> distinct([r], r.thread_id)
    |> order_by([r], asc: r.thread_id, desc: r.inserted_at, desc: r.id)
    |> Repo.all()
    |> Map.new(&{&1.thread_id, &1})
  end

  # Names, states and a Bash call's build progress counts only: a call's
  # arguments and result never leave the server.
  defp tool_calls([]), do: %{}

  defp tool_calls(run_ids) do
    ToolCall
    |> join(:inner, [c], m in Message, on: m.id == c.message_id)
    |> where([c], c.run_id in ^run_ids)
    |> order_by([_c, m], asc: m.position)
    |> select([c, m], {c.run_id, c.name, c.status, m.progress})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2), elem(&1, 3)})
  end

  defp row(thread, run, calls) do
    executing = calls |> Enum.filter(&(elem(&1, 1) == "executing")) |> List.last()
    phase = phase(thread.agent_status, run, executing)
    steps = Enum.count(calls, &(elem(&1, 1) == "completed"))

    trail =
      calls
      |> Enum.map(&trail_phase/1)
      |> Kernel.++([phase])
      # The widget draws a trail's tints, so neighbours of one tint, such as
      # a Once build and the commands after it, are one dot.
      |> Enum.dedup_by(&elem(Map.fetch!(@phases, &1), 2))
      |> Enum.take(-@max_trail)

    %{
      thread: thread,
      phase: phase,
      steps: steps,
      build: if(phase in ["building", "testing"], do: elem(executing, 2)),
      trail: trail,
      started_at: DateTime.to_unix((run && run.inserted_at) || thread.updated_at)
    }
  end

  defp phase("queued", _run, _executing), do: "waiting"
  defp phase("shipping", _run, _executing), do: "shipping"

  defp phase("running", %Run{status: "running"}, {_name, _status, _progress} = call),
    do: tool_phase(call)

  defp phase("running", _run, _executing), do: "thinking"
  defp phase("compacting", _run, _executing), do: "thinking"
  defp phase("idle", _run, _executing), do: "done"
  defp phase("outcome_unknown", _run, _executing), do: "needs_you"
  defp phase(_status, _run, _executing), do: "failed"

  # A call's place in the trail is what it did: a Bash call that ran a Once
  # build or test was Building or Testing, whatever state its last snapshot
  # had when its run or the call ended.
  defp trail_phase({"Bash", _status, %{"command" => "test"}}), do: "testing"
  defp trail_phase({"Bash", _status, %{"command" => "build"}}), do: "building"
  defp trail_phase(call), do: tool_phase(call)

  # A Bash call whose command runs a Once build or test reports its
  # progress in Luft's committed tool-message snapshot.
  # Once that run ended, the command may still run something else.
  defp tool_phase({"Bash", _status, %{"command" => "test", "state" => "running"}}), do: "testing"

  defp tool_phase({"Bash", _status, %{"command" => "build", "state" => "running"}}),
    do: "building"

  defp tool_phase({name, _status, _progress}) when name in ["Read", "Glob", "Grep", "Ls"],
    do: "exploring"

  defp tool_phase({name, _status, _progress}) when name in ["Edit", "Write"], do: "editing"
  defp tool_phase({"Bash", _status, _progress}), do: "running"
  defp tool_phase(_call), do: "working"

  defp rank("needs_you"), do: 0
  defp rank(phase) when phase in ["done", "failed"], do: 1
  defp rank(_phase), do: 2

  defp thread_document(%{thread: thread, phase: phase, steps: steps} = row, server_url) do
    {label, symbol, tint} = Map.fetch!(@phases, phase)

    progress =
      cond do
        phase in @finished -> %{"kind" => "steps", "done" => steps}
        build_total(row.build) > 0 -> build_fraction(row)
        true -> %{"kind" => "timer", "started_at" => row.started_at}
      end

    document = %{
      "id" => thread.id,
      "headline" => headline(thread),
      "detail" =>
        if(row.build, do: build_detail(label, row.build), else: detail(phase, label, steps)),
      "phase" => phase,
      "symbol" => symbol,
      "tint" => tint,
      "progress" => progress,
      "trail" => Enum.map(row.trail, &elem(Map.fetch!(@phases, &1), 2)),
      "link" => link(thread, server_url)
    }

    if phase in @finished,
      do: document,
      else: Map.put(document, "snooze_link", link(thread, server_url, "/snooze"))
  end

  # Luft's own scheme: a widget opens an https link in Safari, not in the app.
  defp link(thread, server_url, suffix \\ ""),
    do: "luft://app/threads/#{thread.id}#{suffix}?" <> URI.encode_query(%{"server" => server_url})

  defp headline(thread) do
    title =
      thread
      |> Delegation.thread_title()
      |> String.replace(~r/[\s\p{Z}\p{Cc}\p{Cf}]+/u, " ")
      |> String.trim()
      |> String.slice(0, @max_title_length)
      |> String.trim()

    if title == "", do: "Your thread", else: title
  end

  # A build's progress stays a `timer`, which widgets that predate `total`
  # keep drawing; newer widgets draw `done` of `total` instead.
  defp build_fraction(row) do
    %{
      "kind" => "timer",
      "started_at" => row.started_at,
      "done" => min(row.build["done"], row.build["planned"]),
      "total" => row.build["planned"]
    }
  end

  defp build_total(%{"planned" => planned}) when is_integer(planned), do: planned
  defp build_total(_build), do: 0

  defp build_detail(label, %{"tests" => %{"passed" => passed, "failed" => failed}})
       when is_integer(passed) and is_integer(failed) and passed + failed > 0,
       do: "#{label} · #{passed} passed, #{failed} failed"

  defp build_detail(label, %{"done" => done, "planned" => planned})
       when is_integer(done) and is_integer(planned) and planned > 0,
       do: "#{label} · #{min(done, planned)} of #{planned} targets"

  defp build_detail(label, _build), do: label

  defp detail("waiting", _label, _steps), do: "Queued"
  defp detail("needs_you", _label, _steps), do: "Check it before continuing"
  defp detail("failed", _label, _steps), do: "Couldn't finish"
  defp detail("done", _label, 0), do: "Replied"
  defp detail("done", _label, steps), do: "Finished in #{steps} #{step_noun(steps)}"
  defp detail(_phase, label, 0), do: label
  defp detail(_phase, label, steps), do: "#{label} · #{steps} #{step_noun(steps)}"

  defp fallback(summary, nil), do: summary["headline"] <> "."

  defp fallback(summary, top),
    do: "#{summary["headline"]}. #{headline(top.thread)}: #{summary["phase"]}."

  defp noun(1), do: "thread"
  defp noun(_count), do: "threads"
  defp step_noun(1), do: "step"
  defp step_noun(_count), do: "steps"

  @doc """
  Retires up to #{@prune_batch_size} registrations past their lifetime and
  deletes up to #{@prune_batch_size} tombstones older than
  #{@tombstone_retention_days} days and push-to-start tokens no app registered
  for #{@starter_stale_days} days.
  """
  def prune do
    now = now()

    expired =
      LiveActivity
      |> where([a], is_nil(a.retired_at) and a.expires_at <= ^now)
      |> limit(@prune_batch_size)
      |> select([a], a.id)

    {retired, _} =
      LiveActivity
      |> where([a], a.id in subquery(expired))
      |> Repo.update_all(set: retired_fields("expired"))

    old =
      LiveActivity
      |> where([a], a.retired_at < ^DateTime.shift(now, day: -@tombstone_retention_days))
      |> limit(@prune_batch_size)
      |> select([a], a.id)

    {deleted, _} = LiveActivity |> where([a], a.id in subquery(old)) |> Repo.delete_all()

    stale_starters =
      LiveActivityStarter
      |> where([s], s.updated_at < ^DateTime.shift(now, day: -@starter_stale_days))
      |> limit(@prune_batch_size)
      |> select([s], s.id)

    {starters, _} =
      LiveActivityStarter |> where([s], s.id in subquery(stale_starters)) |> Repo.delete_all()

    %{retired: retired, deleted: deleted, starters: starters}
  end

  # Advisory locks serialize requests for one registration, including its first
  # insert, and (taken first) the per-user cap.
  defp locked(id, user, fun) do
    Repo.transaction(fn ->
      if user, do: advisory_lock!("thread_live_activity_user:#{user.id}")
      advisory_lock!("thread_live_activity:" <> id)

      LiveActivity
      |> where([a], a.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> fun.()
      |> case do
        {:error, reason} -> Repo.rollback(reason)
        {:ok, value} -> value
        value -> value
      end
    end)
  end

  defp save(registration, user, grant_id, token, environment, hash, changes \\ %{}) do
    # One live registration per token: a restored or reinstalled app reuses it.
    LiveActivity
    |> where([a], a.token_hash == ^hash and is_nil(a.retired_at) and a.id != ^registration.id)
    |> Repo.update_all(set: retired_fields("superseded"))

    saved =
      registration
      |> Ecto.Changeset.change(
        Map.merge(changes, %{
          user_id: user.id,
          oauth_grant_id: grant_id,
          environment: environment,
          token: token,
          token_hash: hash
        })
      )
      |> Repo.insert_or_update!()

    evict_oldest!(user.id)
    {:ok, saved}
  end

  defp evict_oldest!(user_id) do
    keep =
      LiveActivity
      |> where([a], a.user_id == ^user_id and is_nil(a.retired_at))
      |> order_by([a], desc: a.inserted_at, desc: a.id)
      |> limit(@max_live_per_user)
      |> select([a], a.id)

    LiveActivity
    |> where([a], a.user_id == ^user_id and is_nil(a.retired_at) and a.id not in subquery(keep))
    |> Repo.update_all(set: retired_fields("evicted"))
  end

  defp retire!(registration, reason) do
    registration |> Ecto.Changeset.change(retired_fields(reason)) |> Repo.update!()
  end

  defp retired_fields(reason) do
    [
      retired_at: now(),
      retired_reason: reason,
      user_id: nil,
      oauth_grant_id: nil,
      token: nil,
      token_hash: nil,
      last_digest: nil,
      last_phase_digest: nil,
      working_thread_ids: []
    ]
  end

  defp advisory_lock!(key),
    do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp exact_session(user, grant_id) do
    if user.session_id == grant_id and Delegation.active?(grant_id, user.id),
      do: :ok,
      else: {:error, :invalid}
  end

  defp validate_id(id) when is_binary(id) do
    if Regex.match?(@uuid, id), do: {:ok, id}, else: {:error, :invalid}
  end

  defp validate_id(_id), do: {:error, :invalid}

  defp validate_params(%{"token" => token, "environment" => environment})
       when is_binary(token) and environment in ["sandbox", "production"] do
    if Regex.match?(@token, token),
      do: {:ok, String.downcase(token), environment},
      else: {:error, :invalid}
  end

  defp validate_params(_params), do: {:error, :invalid}
end
