defmodule Atlas.Orbit do
  @moduledoc """
  Orbit: persistent private and shared threads with the Atlas assistant.

  Every person can have multiple private conversations with the assistant. Shared
  threads have an owner and participants, and may be opened by a person or
  by a monitored signal (`open_for_signal/1`). The thread is the agentic
  session: messages, tool calls, and assistant replies form one ordered log.

  Reads, posts, membership, and assistant runs all go through
  `Atlas.Orbit.Access`. See `lib/atlas/orbit/AGENTS.md`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Authorization
  alias Atlas.Authorization.Role
  alias Atlas.Authorization.UserRole
  alias Atlas.Inference
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Attachments
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Participant
  alias Atlas.Orbit.Rendering
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Workers.RunThread
  alias Atlas.Push
  alias Atlas.RateLimit
  alias Atlas.Repo
  alias Atlas.Users.User

  @thread_page_size 25
  @message_page_size 50
  @max_participants 30
  @max_body_bytes 16_000
  @message_rate_limit 30
  @message_rate_window :timer.minutes(1)
  @private_title "New conversation"
  @notification_channel :atlas_orbit

  ## Assistant

  def agent_name, do: "Pip"

  def agent_configured?, do: Inference.atlas_role_configured?(:orbit)

  def agent_configured?(%User{} = user), do: Runner.orbit_configured?(user)

  def message_page_size, do: @message_page_size

  ## Notifications

  def subscribe(thread_id), do: Phoenix.PubSub.subscribe(Atlas.PubSub, topic(thread_id))

  def subscribe_run(run_id), do: Phoenix.PubSub.subscribe(Atlas.PubSub, run_topic(run_id))

  def subscribe_list, do: Phoenix.PubSub.subscribe(Atlas.PubSub, list_topic())

  def topic(thread_id), do: "orbit:thread:#{thread_id}"
  def list_topic, do: "orbit:threads"
  def run_topic(run_id), do: "orbit_run:#{run_id}"

  def notification_channel, do: @notification_channel

  @doc "Tells every replica that a thread changed. Payloads carry ids only."
  def notify_changed(thread_id) do
    Oban.Notifier.notify(Oban, @notification_channel, %{"thread_id" => thread_id})
  end

  def notify_cancel(run_id) do
    Oban.Notifier.notify(Oban, @notification_channel, %{"cancel_run_id" => run_id})
  end

  ## Reads

  def list_for_user(%User{} = user, page \\ 1, kind \\ nil) do
    scopes = Atlas.Users.scopes_for(user)

    query =
      from thread in Thread,
        join: participant in Participant,
        on: participant.thread_id == thread.id and participant.user_id == ^user.id,
        where:
          fragment(
            "?::text[] <@ ?::text[]",
            thread.required_scopes,
            type(^scopes, {:array, :string})
          )

    query = if kind in ["private", "shared"], do: where(query, [thread], thread.kind == ^kind), else: query
    total_count = Repo.aggregate(query, :count)
    total_pages = max(1, ceil(total_count / @thread_page_size))
    page = page |> max(1) |> min(total_pages)

    items =
      query
      |> order_by([thread],
        asc: fragment("CASE WHEN ? = 'private' THEN 0 ELSE 1 END", thread.kind),
        desc: thread.updated_at,
        desc: thread.id
      )
      |> limit(^@thread_page_size)
      |> offset(^((page - 1) * @thread_page_size))
      |> preload_participants()
      |> Repo.all()

    {items, %{page: page, total_pages: total_pages, total_count: total_count}}
  end

  @doc """
  A non-negative fingerprint of every thread `user` can currently read
  and its latest change. It moves when a thread appears, disappears, or
  changes, and reveals nothing else.
  """
  def list_revision(%User{} = user) do
    scopes = Atlas.Users.scopes_for(user)

    from(thread in Thread,
      join: participant in Participant,
      on: participant.thread_id == thread.id and participant.user_id == ^user.id,
      where: fragment("?::text[] <@ ?::text[]", thread.required_scopes, type(^scopes, {:array, :string})),
      order_by: thread.id,
      select: {thread.id, thread.last_seq, thread.status}
    )
    |> Repo.all()
    |> :erlang.phash2(4_294_967_296)
  end

  @doc "Returns the thread when `user` can currently read it, otherwise `{:error, :not_found}`."
  def fetch(%User{} = user, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Thread{} = thread <- Repo.get(Thread, id),
         true <- Access.can_read?(thread, user) do
      {:ok, Repo.preload(thread, participants: :user)}
    else
      _ -> {:error, :not_found}
    end
  end

  def fetch(_user, _id), do: {:error, :not_found}

  @doc "Name-only mention choices; only owners may discover people outside the current audience."
  def mention_people(%User{} = user, %Thread{id: id}, query \\ "") do
    with true <-
           is_binary(query) and byte_size(query) <= 100 and String.valid?(query) and not String.contains?(query, <<0>>),
         {:ok, thread} <- fetch(user, id),
         :ok <- if(thread.status == "active", do: :ok, else: {:error, :archived}) do
      pattern =
        "%" <>
          (query
           |> String.trim()
           |> String.replace("\\", "\\\\")
           |> String.replace("%", "\\%")
           |> String.replace("_", "\\_")) <> "%"

      candidates =
        from person in User,
          as: :person,
          where: person.id != ^user.id and ilike(person.name, ^pattern),
          order_by: [asc: fragment("lower(?)", person.name), asc: person.id]

      candidates =
        if thread.owner_id == user.id do
          candidates
        else
          where(
            candidates,
            [person],
            person.id in subquery(from p in Participant, where: p.thread_id == ^thread.id, select: p.user_id)
          )
        end

      candidates =
        Enum.reduce(thread.required_scopes, candidates, fn scope, candidates ->
          grants =
            if String.ends_with?(scope, ":read"),
              do: [scope, String.replace_suffix(scope, ":read", ":write")],
              else: [scope]

          where(
            candidates,
            exists(
              from role in Role,
                join: assignment in UserRole,
                on: assignment.role_id == role.id,
                where: assignment.user_id == parent_as(:person).id,
                where: fragment("?::text[] && ?::text[]", role.scopes, ^grants),
                select: 1
            )
          )
        end)

      people =
        candidates
        |> limit(20)
        |> select([person], struct(person, [:id, :name]))
        |> Repo.all()
        |> Enum.filter(&Access.holds_all?(&1, thread.required_scopes))
        |> Enum.map(&%{id: &1.id, name: &1.name})

      {:ok, people}
    else
      false -> {:error, {:invalid_field, :query}}
      error -> error
    end
  end

  def list_messages(%Thread{id: thread_id}, page \\ 1) do
    query = from(message in Message, where: message.thread_id == ^thread_id)
    total_count = Repo.aggregate(query, :count)
    total_pages = max(1, ceil(total_count / @message_page_size))
    page = page |> max(1) |> min(total_pages)

    items =
      query
      |> order_by(desc: :position)
      |> limit(^@message_page_size)
      |> offset(^((page - 1) * @message_page_size))
      |> preload([:author, :attachments])
      |> Repo.all()
      |> Enum.reverse()

    {items, %{page: page, total_pages: total_pages, total_count: total_count}}
  end

  def active_run(%Thread{id: thread_id}) do
    Repo.one(
      from run in Run,
        where: run.thread_id == ^thread_id and run.status in ^Run.active_statuses(),
        limit: 1
    )
  end

  ## Creation

  @doc "Returns the caller's latest private thread, creating it only on first use."
  def ensure_private(%User{} = user) do
    private_transaction(user, fn ->
      case private_for(user) do
        %Thread{} = thread -> {thread, :existing}
        nil -> {insert_private!(user, nil), :created}
      end
    end)
  end

  @doc "Creates a distinct owner-only conversation; a request UUID replays the same creation."
  def create_private(%User{} = user, attrs) when is_map(attrs) do
    case cast_uuid(attrs["request_id"]) do
      {:ok, request_id} ->
        private_transaction(user, fn ->
          case Repo.get_by(Thread, owner_id: user.id, request_id: request_id) do
            %Thread{kind: "private"} = thread -> {thread, :existing}
            %Thread{} -> Repo.rollback(:thread_promoted)
            nil -> {insert_private!(user, request_id), :created}
          end
        end)

      :error ->
        {:error, {:invalid_field, :request_id}}
    end
  end

  defp private_transaction(user, action) do
    Repo.transaction(fn ->
      # Also serialize legacy first-use requests now that private threads are not unique per owner.
      Repo.one!(from owner in User, where: owner.id == ^user.id, lock: "FOR UPDATE")
      action.()
    end)
    |> case do
      {:ok, {thread, disposition}} ->
        if disposition == :created do
          Audit.record("thread.created", thread_audit(thread, user))
          notify_changed(thread.id)
        end

        {:ok, preload_thread(thread), disposition}

      error ->
        error
    end
  end

  defp insert_private!(user, request_id) do
    with {:ok, thread} <-
           %{kind: "private", title: @private_title, owner_id: user.id, request_id: request_id}
           |> Thread.create_changeset()
           |> Repo.insert(),
         {:ok, _participant} <- insert_participant(thread, user.id, "owner") do
      thread
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp private_for(%User{id: user_id}) do
    Thread
    |> where([thread], thread.kind == "private" and thread.owner_id == ^user_id)
    |> order_by([thread], desc: thread.updated_at, desc: thread.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      thread -> preload_thread(thread)
    end
  end

  def create_shared(%User{} = user, attrs) when is_map(attrs) do
    with {:ok, participant_ids} <- participant_ids(attrs, user),
         {:ok, users} <- load_users(participant_ids) do
      Repo.transaction(fn ->
        with {:ok, thread} <-
               %{kind: "shared", title: attrs["title"] || "", owner_id: user.id}
               |> Thread.create_changeset()
               |> Repo.insert(),
             {:ok, _owner} <- insert_participant(thread, user.id, "owner"),
             :ok <- insert_members(thread, users) do
          thread
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, thread} ->
          Audit.record("thread.created", thread_audit(thread, user))
          {:ok, preload_thread(thread)}

        error ->
          error
      end
    end
  end

  defp participant_ids(attrs, %User{id: owner_id}) do
    with ids when is_list(ids) and length(ids) <= @max_participants <- Map.get(attrs, "participant_ids", []),
         casted = Enum.map(ids, &cast_uuid/1),
         true <- Enum.all?(casted, &match?({:ok, _}, &1)) do
      {:ok, casted |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.reject(&(&1 == owner_id))}
    else
      _ -> {:error, {:invalid_field, :participant_ids}}
    end
  end

  defp load_users([]), do: {:ok, []}

  defp load_users(ids) do
    users = Repo.all(from user in User, where: user.id in ^ids)

    if length(users) == length(ids), do: {:ok, users}, else: {:error, {:invalid_field, :participant_ids}}
  end

  defp insert_members(thread, users) do
    Enum.reduce_while(users, :ok, fn user, :ok ->
      case insert_participant(thread, user.id, "member") do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp insert_participant(%Thread{id: thread_id}, user_id, role) do
    Repo.insert(%Participant{thread_id: thread_id, user_id: user_id, role: role})
  end

  ## Membership

  @doc """
  Adds a participant. Only the owner of a shared thread may add people,
  and the new participant must already hold every scope the thread's
  history requires. An active assistant run is cancelled, because it may have
  read data for the previous audience.
  """
  def add_participant(%User{} = actor, %Thread{} = thread, user_id) do
    with {:ok, user_id} <- cast_uuid(user_id),
         %User{} = user <- Repo.get(User, user_id) do
      Repo.transaction(fn ->
        thread = lock!(thread.id)
        ensure_active_reader!(thread, actor)

        cond do
          thread.kind != "shared" or thread.owner_id != actor.id ->
            Repo.rollback(:forbidden)

          not Access.holds_all?(user, thread.required_scopes) ->
            Repo.rollback(:missing_access)

          Access.participant?(thread, user) ->
            :existing

          true ->
            {:ok, _participant} = insert_participant(thread, user.id, "member")
            cancel_active_runs(thread, "participants_changed")
            append!(thread, %{kind: "system", body: "#{display_name(actor)} added #{display_name(user)}."})
            append_handoff!(thread)
            :added
        end
      end)
      |> case do
        {:ok, result} ->
          if result == :added do
            Audit.record(
              "thread.participant_added",
              thread_audit(thread, actor, %{"user_id" => user.id})
            )

            notify_changed(thread.id)
          end

          {:ok, user}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _ -> {:error, {:invalid_field, :user_id}}
    end
  end

  @doc "Owners remove others; members remove themselves. Owners cannot leave."
  def remove_participant(%User{} = actor, %Thread{} = thread, user_id) do
    with {:ok, user_id} <- cast_uuid(user_id),
         {:ok, 1} <- Repo.transaction(fn -> remove_locked(actor, thread.id, user_id) end) do
      Audit.record("thread.participant_removed", thread_audit(thread, actor, %{"user_id" => user_id}))
      notify_changed(thread.id)
      :ok
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp remove_locked(actor, thread_id, user_id) do
    thread = lock!(thread_id)

    allowed? =
      thread.kind == "shared" and user_id != thread.owner_id and
        actor.id in [thread.owner_id, user_id]

    if !allowed?, do: Repo.rollback(:forbidden)

    {count, _} =
      Repo.delete_all(
        from participant in Participant,
          where: participant.thread_id == ^thread.id and participant.user_id == ^user_id
      )

    if count == 1, do: append!(thread, %{kind: "system", body: removal_notice(actor, user_id)})
    count
  end

  defp removal_notice(%User{id: user_id}, user_id), do: "#{User |> Repo.get(user_id) |> display_name()} left."

  defp removal_notice(actor, user_id),
    do: "#{display_name(actor)} removed #{User |> Repo.get(user_id) |> display_name()}."

  ## Messages

  @doc """
  Posts a human message. `client_id` makes retries idempotent per author.
  Messages addressed to the assistant start a run when none is active; a run
  that is already in progress picks them up in a follow-up when it finishes.
  """
  def post_message(%User{} = user, %Thread{} = thread, attrs) when is_map(attrs) do
    with {:ok, attachment_ids} <- Attachments.ids(attrs),
         {:ok, body} <- message_body(attrs, attachment_ids),
         {:ok, client_id} <- client_id(attrs),
         :ok <- rate_limit(user) do
      fn -> post_locked(user, thread.id, body, client_id, attrs, attachment_ids) end
      |> Repo.transaction()
      |> case do
        {:ok, {message, :created}} ->
          notify_changed(thread.id)
          {:ok, Repo.preload(message, [:author, :attachments]), :created}

        {:ok, {message, :existing}} ->
          {:ok, Repo.preload(message, [:author, :attachments]), :existing}

        error ->
          error
      end
    end
  end

  defp post_locked(user, thread_id, body, client_id, attrs, attachment_ids) do
    thread = lock!(thread_id)
    ensure_active_reader!(thread, user)

    if existing = existing_message(thread, user, client_id) do
      {existing, :existing}
    else
      {thread, newcomers} = apply_mentions!(thread, user, attrs)
      maybe_title_private(thread, body)
      address_agent? = thread.kind == "private" or Map.get(attrs, "address_agent", true) != false

      message =
        append!(thread, %{
          kind: "human",
          body: body,
          author_id: user.id,
          author_name: display_name(user),
          client_id: client_id,
          mentioned_user_ids: mention_ids!(attrs),
          address_agent: address_agent?
        })

      Attachments.claim!(attachment_ids, user, message)
      if newcomers != [], do: append_handoff!(thread)
      queue_mentions!(thread, message, user)
      if address_agent?, do: request_run!(thread, message, user, user)
      {message, :created}
    end
  end

  defp ensure_active_reader!(thread, user) do
    cond do
      thread.status != "active" -> Repo.rollback(:archived)
      not Access.can_read?(thread, user) -> Repo.rollback(:not_found)
      true -> :ok
    end
  end

  defp mention_ids!(attrs) do
    with ids when is_list(ids) and length(ids) <= 10 <- Map.get(attrs, "mention_ids", []),
         casted = Enum.map(ids, &cast_uuid/1),
         true <- Enum.all?(casted, &match?({:ok, _}, &1)) do
      casted |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    else
      _ -> Repo.rollback({:invalid_field, :mention_ids})
    end
  end

  defp apply_mentions!(thread, actor, attrs) do
    ids = mention_ids!(attrs)
    users = Repo.all(from user in User, where: user.id in ^ids)

    if length(users) != length(ids) or not Enum.all?(users, &Access.holds_all?(&1, thread.required_scopes)),
      do: Repo.rollback({:invalid_field, :mention_ids})

    newcomers = Enum.reject(users, &Access.participant?(thread, &1))

    if newcomers == [] do
      {thread, []}
    else
      if thread.owner_id != actor.id, do: Repo.rollback(:forbidden)
      count = Repo.aggregate(from(p in Participant, where: p.thread_id == ^thread.id), :count)
      if count + length(newcomers) > @max_participants + 1, do: Repo.rollback({:invalid_field, :mention_ids})

      promoted? = thread.kind == "private"

      thread =
        thread |> Ecto.Changeset.change(kind: "shared", title: promotion_title(thread, attrs["body"])) |> Repo.update!()

      :ok = insert_members(thread, newcomers)
      cancel_active_runs(thread, "participants_changed")

      if promoted?, do: Audit.record("thread.promoted", thread_audit(thread, actor))

      Enum.each(newcomers, fn person ->
        Audit.record("thread.participant_added", thread_audit(thread, actor, %{"user_id" => person.id}))
      end)

      {thread, newcomers}
    end
  end

  defp promotion_title(thread, body) do
    if String.trim(thread.title) in ["", "Pip", @private_title] do
      prompt = first_prompt(thread) || body || ""

      title =
        prompt |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.codepoints() |> Enum.take(200) |> Enum.join()

      if title == "", do: @private_title, else: title
    else
      thread.title
    end
  end

  defp first_prompt(thread) do
    Repo.one(
      from message in Message,
        where:
          message.thread_id == ^thread.id and message.kind == "human" and fragment("? ~ '[^[:space:]]'", message.body),
        order_by: [asc: message.position],
        limit: 1,
        select: message.body
    )
  end

  defp append_handoff!(thread) do
    reply =
      Repo.one(
        from message in Message,
          where:
            message.thread_id == ^thread.id and message.kind == "agent" and fragment("? ~ '[^[:space:]]'", message.body),
          order_by: [desc: message.position],
          limit: 1,
          select: message.body
      )

    body =
      "Conversation so far — excerpts for new participants (not an AI-generated summary).\n\n" <>
        "Initial request (excerpt):\n" <>
        handoff_excerpt(first_prompt(thread)) <>
        "\n\nLatest Pip reply (excerpt):\n" <> handoff_excerpt(reply)

    append!(thread, %{kind: "system", notice_kind: "handoff", body: body})
  end

  defp handoff_excerpt(nil), do: "> No text yet."

  defp handoff_excerpt(text) do
    text
    |> String.codepoints()
    |> Enum.take(800)
    |> Enum.join()
    |> String.split("\n")
    |> Enum.map_join("\n", &("> " <> &1))
  end

  defp queue_mentions!(thread, message, actor) do
    for id <- message.mentioned_user_ids, id != actor.id do
      {:ok, _count} = Push.notify_user(id, "orbit_mentioned", {"orbit", thread.id}, message_id: message.id)
    end
  end

  defp maybe_title_private(%Thread{kind: "private"} = thread, body) when body != "" do
    previous_prompt? =
      Repo.exists?(
        from message in Message,
          where: message.thread_id == ^thread.id and message.kind == "human" and message.body != ""
      )

    if !previous_prompt? do
      title = body |> String.replace(~r/\s+/u, " ") |> String.codepoints() |> Enum.take(200) |> Enum.join()
      thread |> Ecto.Changeset.change(title: title) |> Repo.update!()
    end
  end

  defp maybe_title_private(_thread, _body), do: :ok

  defp message_body(attrs, attachment_ids) do
    case Map.get(attrs, "body", "") do
      body when is_binary(body) ->
        trimmed = String.trim(body)

        if (trimmed != "" or attachment_ids != []) and byte_size(body) <= @max_body_bytes,
          do: {:ok, trimmed},
          else: {:error, {:invalid_field, :body}}

      _ ->
        {:error, {:invalid_field, :body}}
    end
  end

  defp client_id(attrs) do
    case cast_uuid(Map.get(attrs, "client_id")) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_field, :client_id}}
    end
  end

  defp rate_limit(%User{id: user_id}) do
    case RateLimit.hit("thread_message:#{user_id}", @message_rate_window, @message_rate_limit) do
      {:allow, _attempts} -> :ok
      {:deny, _remaining} -> {:error, :rate_limited}
    end
  end

  defp existing_message(thread, user, client_id) do
    Repo.one(
      from message in Message,
        where:
          message.thread_id == ^thread.id and message.author_id == ^user.id and
            message.client_id == ^client_id
    )
  end

  ## Runs

  @doc "Requests cancellation of an active run. The initiator and the owner may cancel."
  def cancel_run(%User{} = user, %Thread{} = thread, run_id) do
    with {:ok, run_id} <- cast_uuid(run_id),
         %Run{} = run <- Repo.get_by(Run, id: run_id, thread_id: thread.id),
         true <- run.status in Run.active_statuses(),
         true <- user.id in [run.initiator_id, thread.owner_id] do
      Repo.update_all(
        from(run in Run, where: run.id == ^run.id and is_nil(run.cancel_requested_at)),
        set: [cancel_requested_at: DateTime.utc_now()]
      )

      notify_cancel(run.id)
      {:ok, Repo.get(Run, run.id)}
    else
      _ -> {:error, :not_found}
    end
  end

  # Inside a transaction holding the thread lock. Starts a run unless one
  # is already active; the active run's follow-up covers this message.
  defp request_run!(thread, %Message{} = trigger, initiator, acting_user) do
    cond do
      active_run(thread) ->
        :pending

      not agent_configured?(acting_user) ->
        append!(thread, %{
          kind: "system",
          body: "Connect an AI account in Settings, or ask an administrator to assign an inference profile to Orbit."
        })

        :unconfigured

      true ->
        start_run!(thread, trigger.position, initiator, acting_user)
    end
  end

  @doc false
  def start_run!(thread, trigger_seq, initiator, acting_user) do
    model_binding_id =
      case Inference.fetch_atlas_role(:orbit) do
        {:ok, binding, _token} -> binding.id
        _ -> nil
      end

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        initiator_id: initiator && initiator.id,
        acting_user_id: acting_user.id,
        model_binding_id: model_binding_id,
        trigger_seq: trigger_seq,
        status: "queued"
      })

    {:ok, _job} = %{"run_id" => run.id, "resume" => 0} |> RunThread.new() |> Oban.insert()
    run
  end

  defp cancel_active_runs(thread, _reason) do
    runs =
      Repo.all(
        from run in Run,
          where: run.thread_id == ^thread.id and run.status in ^Run.active_statuses(),
          select: run.id
      )

    Repo.update_all(
      from(run in Run, where: run.id in ^runs and is_nil(run.cancel_requested_at)),
      set: [cancel_requested_at: DateTime.utc_now()]
    )

    Enum.each(runs, &notify_cancel/1)
  end

  ## Signals

  @doc """
  Opens (or appends to) a shared thread for a monitored signal.

  Required keys: `:owner_id`, `:source_type`, `:source_id`, `:title`, and
  `:summary`. Optional: `:participant_ids` and `:required_scopes`, the access
  the summary itself requires. The owner and every participant must hold those
  scopes; nobody is silently dropped. The assistant acts as the owner, limited
  to what every participant may see, and is re-authorized on every tool call.
  Repeated signals for the same active source append to the same thread.
  """
  def open_for_signal(attrs) when is_map(attrs) do
    with {:ok, owner_id} <- cast_uuid(attrs[:owner_id]),
         %User{} = owner <- Repo.get(User, owner_id),
         {:ok, participant_ids} <- participant_ids(%{"participant_ids" => attrs[:participant_ids] || []}, owner),
         {:ok, participants} <- load_users(participant_ids),
         {:ok, scopes} <- signal_scopes(attrs[:required_scopes] || []),
         :ok <- ensure_holds_all([owner | participants], scopes),
         {:ok, source_type, source_id, title, summary} <- signal_fields(attrs) do
      Repo.transaction(fn ->
        thread =
          case active_signal_thread(source_type, source_id) do
            nil ->
              {:ok, thread} =
                %{
                  kind: "shared",
                  title: title,
                  summary: summary,
                  origin: "signal",
                  source_type: source_type,
                  source_id: source_id,
                  owner_id: owner.id,
                  required_scopes: scopes
                }
                |> Thread.create_changeset()
                |> Repo.insert()

              {:ok, _} = insert_participant(thread, owner.id, "owner")
              :ok = insert_members(thread, participants)
              lock!(thread.id)

            existing ->
              lock!(existing.id)
          end

        message = append!(thread, %{kind: "system", body: summary, address_agent: true})

        if Access.can_read?(thread, Repo.get(User, thread.owner_id)) do
          request_run!(thread, message, nil, Repo.get(User, thread.owner_id))
        end

        thread
      end)
      |> case do
        {:ok, thread} ->
          Audit.record(
            "thread.signal_received",
            thread_audit(thread, nil, %{"source_type" => source_type, "source_id" => source_id})
          )

          notify_changed(thread.id)
          {:ok, preload_thread(Repo.get!(Thread, thread.id))}

        error ->
          error
      end
    else
      nil -> {:error, {:invalid_field, :owner_id}}
      :error -> {:error, {:invalid_field, :owner_id}}
      {:error, _} = error -> error
    end
  end

  defp ensure_holds_all(users, scopes) do
    if Enum.all?(users, &Access.holds_all?(&1, scopes)), do: :ok, else: {:error, :missing_access}
  end

  defp signal_scopes(scopes) when is_list(scopes) do
    if Enum.all?(scopes, &(&1 in Authorization.all_scopes())),
      do: {:ok, Enum.uniq(scopes)},
      else: {:error, {:invalid_field, :required_scopes}}
  end

  defp signal_scopes(_scopes), do: {:error, {:invalid_field, :required_scopes}}

  defp signal_fields(attrs) do
    with source_type when is_binary(source_type) and source_type != "" <- attrs[:source_type],
         source_id when is_binary(source_id) and source_id != "" <- attrs[:source_id],
         title when is_binary(title) and title != "" <- attrs[:title],
         summary when is_binary(summary) and summary != "" <- attrs[:summary] do
      {:ok, String.slice(source_type, 0, 100), String.slice(source_id, 0, 200),
       String.slice(String.trim(title), 0, 200), Rendering.truncate(summary, 2_000)}
    else
      _ -> {:error, {:invalid_field, :signal}}
    end
  end

  defp active_signal_thread(source_type, source_id) do
    Repo.one(
      from thread in Thread,
        where:
          thread.origin == "signal" and thread.status == "active" and
            thread.source_type == ^source_type and thread.source_id == ^source_id
    )
  end

  ## Log primitives

  @doc false
  def lock!(thread_id) do
    Repo.one!(from thread in Thread, where: thread.id == ^thread_id, lock: "FOR UPDATE")
  end

  @doc false
  # Appends a message, allocating the next sequence number. Must run inside a
  # transaction; the sequence update takes the thread row lock.
  def append!(%Thread{id: thread_id}, attrs) do
    seq = next_seq!(thread_id)

    Repo.insert!(struct(Message, Map.merge(attrs, %{thread_id: thread_id, position: seq, seq: seq})))
  end

  @doc false
  def touch!(%Message{} = message, changes) do
    seq = next_seq!(message.thread_id)

    message
    |> Ecto.Changeset.change(Map.put(changes, :seq, seq))
    |> Repo.update!()
  end

  defp next_seq!(thread_id) do
    {1, [seq]} =
      Repo.update_all(
        from(thread in Thread, where: thread.id == ^thread_id, select: thread.last_seq),
        inc: [last_seq: 1],
        set: [updated_at: DateTime.utc_now()]
      )

    seq
  end

  ## Helpers

  def display_name(%User{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%User{email: email}), do: email
  def display_name(_user), do: "Someone"

  defp preload_thread(thread), do: Repo.preload(thread, [participants: :user], force: true)

  defp preload_participants(query), do: preload(query, participants: :user)

  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, String.downcase(uuid)}
      :error -> :error
    end
  end

  defp cast_uuid(_value), do: :error

  defp thread_audit(thread, actor, metadata \\ %{}) do
    %{
      target_type: "thread",
      target_id: thread.id,
      target_label: thread.kind,
      metadata: Map.merge(%{"kind" => thread.kind, "origin" => thread.origin}, metadata)
    }
    |> then(fn attrs -> if actor, do: Map.put(attrs, :actor, actor), else: attrs end)
  end
end
