defmodule Atlas.Conversations do
  @moduledoc """
  Conversations between people and the Atlas assistant.

  Every person has one pinned private thread with the assistant. Shared
  conversations have an owner and participants, and may be opened by a person or
  by a monitored signal (`open_for_signal/1`). The conversation is the agentic
  session: messages, tool calls, and assistant replies form one ordered log.

  Reads, posts, membership, and assistant runs all go through
  `Atlas.Conversations.Access`. See `lib/atlas/conversations/AGENTS.md`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Authorization
  alias Atlas.Conversations.Access
  alias Atlas.Conversations.Conversation
  alias Atlas.Conversations.Message
  alias Atlas.Conversations.Participant
  alias Atlas.Conversations.Rendering
  alias Atlas.Conversations.Run
  alias Atlas.Conversations.Workers.RunConversation
  alias Atlas.Inference
  alias Atlas.RateLimit
  alias Atlas.Repo
  alias Atlas.Users.User

  @conversation_page_size 25
  @message_page_size 50
  @max_participants 30
  @max_body_bytes 16_000
  @message_rate_limit 30
  @message_rate_window :timer.minutes(1)
  @private_title "Private conversation"
  @notification_channel :atlas_conversations

  ## Configuration

  def agent_name do
    :atlas
    |> Application.get_env(:conversations, [])
    |> Keyword.get(:agent_name)
    |> case do
      name when is_binary(name) and name != "" -> name
      _ -> "Atlas"
    end
  end

  def agent_configured?, do: Inference.atlas_role_configured?(:conversations)

  def message_page_size, do: @message_page_size

  ## Notifications

  def subscribe(conversation_id), do: Phoenix.PubSub.subscribe(Atlas.PubSub, topic(conversation_id))

  def subscribe_run(run_id), do: Phoenix.PubSub.subscribe(Atlas.PubSub, run_topic(run_id))

  def subscribe_list, do: Phoenix.PubSub.subscribe(Atlas.PubSub, list_topic())

  def topic(conversation_id), do: "conversation:#{conversation_id}"
  def list_topic, do: "conversations"
  def run_topic(run_id), do: "conversation_run:#{run_id}"

  def notification_channel, do: @notification_channel

  @doc "Tells every replica that a conversation changed. Payloads carry ids only."
  def notify_changed(conversation_id) do
    Oban.Notifier.notify(Oban, @notification_channel, %{"conversation_id" => conversation_id})
  end

  def notify_cancel(run_id) do
    Oban.Notifier.notify(Oban, @notification_channel, %{"cancel_run_id" => run_id})
  end

  ## Reads

  def list_for_user(%User{} = user, page \\ 1) do
    scopes = Atlas.Users.scopes_for(user)

    query =
      from conversation in Conversation,
        join: participant in Participant,
        on: participant.conversation_id == conversation.id and participant.user_id == ^user.id,
        where:
          fragment(
            "?::text[] <@ ?::text[]",
            conversation.required_scopes,
            type(^scopes, {:array, :string})
          )

    total_count = Repo.aggregate(query, :count)
    total_pages = max(1, ceil(total_count / @conversation_page_size))
    page = page |> max(1) |> min(total_pages)

    items =
      query
      |> order_by([conversation],
        asc: fragment("CASE WHEN ? = 'private' THEN 0 ELSE 1 END", conversation.kind),
        desc: conversation.updated_at,
        desc: conversation.id
      )
      |> limit(^@conversation_page_size)
      |> offset(^((page - 1) * @conversation_page_size))
      |> preload_participants()
      |> Repo.all()

    {items, %{page: page, total_pages: total_pages, total_count: total_count}}
  end

  @doc """
  A non-negative fingerprint of every conversation `user` can currently read
  and its latest change. It moves when a conversation appears, disappears, or
  changes, and reveals nothing else.
  """
  def list_revision(%User{} = user) do
    scopes = Atlas.Users.scopes_for(user)

    from(conversation in Conversation,
      join: participant in Participant,
      on: participant.conversation_id == conversation.id and participant.user_id == ^user.id,
      where: fragment("?::text[] <@ ?::text[]", conversation.required_scopes, type(^scopes, {:array, :string})),
      order_by: conversation.id,
      select: {conversation.id, conversation.last_seq, conversation.status}
    )
    |> Repo.all()
    |> :erlang.phash2(4_294_967_296)
  end

  @doc "Returns the conversation when `user` can currently read it, otherwise `{:error, :not_found}`."
  def fetch(%User{} = user, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Conversation{} = conversation <- Repo.get(Conversation, id),
         true <- Access.can_read?(conversation, user) do
      {:ok, Repo.preload(conversation, participants: :user)}
    else
      _ -> {:error, :not_found}
    end
  end

  def fetch(_user, _id), do: {:error, :not_found}

  def list_messages(%Conversation{id: conversation_id}, page \\ 1) do
    query = from(message in Message, where: message.conversation_id == ^conversation_id)
    total_count = Repo.aggregate(query, :count)
    total_pages = max(1, ceil(total_count / @message_page_size))
    page = page |> max(1) |> min(total_pages)

    items =
      query
      |> order_by(desc: :position)
      |> limit(^@message_page_size)
      |> offset(^((page - 1) * @message_page_size))
      |> preload(:author)
      |> Repo.all()
      |> Enum.reverse()

    {items, %{page: page, total_pages: total_pages, total_count: total_count}}
  end

  def active_run(%Conversation{id: conversation_id}) do
    Repo.one(
      from run in Run,
        where: run.conversation_id == ^conversation_id and run.status in ^Run.active_statuses(),
        limit: 1
    )
  end

  ## Creation

  @doc "Returns the caller's pinned private thread, creating it on first use."
  def ensure_private(%User{} = user) do
    case private_for(user) do
      %Conversation{} = conversation ->
        {:ok, conversation, :existing}

      nil ->
        Repo.transaction(fn ->
          with {:ok, conversation} <-
                 %{kind: "private", title: @private_title, owner_id: user.id}
                 |> Conversation.create_changeset()
                 |> Repo.insert(),
               {:ok, _participant} <- insert_participant(conversation, user.id, "owner") do
            conversation
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, conversation} ->
            Audit.record("conversation.created", conversation_audit(conversation, user))
            {:ok, preload_conversation(conversation), :created}

          {:error, %Ecto.Changeset{}} ->
            # A concurrent request created it first.
            case private_for(user) do
              %Conversation{} = conversation -> {:ok, conversation, :existing}
              nil -> {:error, :conflict}
            end
        end
    end
  end

  defp private_for(%User{id: user_id}) do
    Conversation
    |> where([conversation], conversation.kind == "private" and conversation.owner_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> nil
      conversation -> preload_conversation(conversation)
    end
  end

  def create_shared(%User{} = user, attrs) when is_map(attrs) do
    with {:ok, participant_ids} <- participant_ids(attrs, user),
         {:ok, users} <- load_users(participant_ids) do
      Repo.transaction(fn ->
        with {:ok, conversation} <-
               %{kind: "shared", title: attrs["title"] || "", owner_id: user.id}
               |> Conversation.create_changeset()
               |> Repo.insert(),
             {:ok, _owner} <- insert_participant(conversation, user.id, "owner"),
             :ok <- insert_members(conversation, users) do
          conversation
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, conversation} ->
          Audit.record("conversation.created", conversation_audit(conversation, user))
          {:ok, preload_conversation(conversation)}

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

  defp insert_members(conversation, users) do
    Enum.reduce_while(users, :ok, fn user, :ok ->
      case insert_participant(conversation, user.id, "member") do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp insert_participant(%Conversation{id: conversation_id}, user_id, role) do
    Repo.insert(%Participant{conversation_id: conversation_id, user_id: user_id, role: role})
  end

  ## Membership

  @doc """
  Adds a participant. Only the owner of a shared conversation may add people,
  and the new participant must already hold every scope the conversation's
  history requires. An active assistant run is cancelled, because it may have
  read data for the previous audience.
  """
  def add_participant(%User{} = actor, %Conversation{} = conversation, user_id) do
    with {:ok, user_id} <- cast_uuid(user_id),
         %User{} = user <- Repo.get(User, user_id) do
      Repo.transaction(fn ->
        conversation = lock!(conversation.id)

        cond do
          conversation.kind != "shared" or conversation.owner_id != actor.id ->
            Repo.rollback(:forbidden)

          not Access.holds_all?(user, conversation.required_scopes) ->
            Repo.rollback(:missing_access)

          Access.participant?(conversation, user) ->
            :existing

          true ->
            {:ok, _participant} = insert_participant(conversation, user.id, "member")
            cancel_active_runs(conversation, "participants_changed")
            append!(conversation, %{kind: "system", body: "#{display_name(actor)} added #{display_name(user)}."})
            :added
        end
      end)
      |> case do
        {:ok, result} ->
          if result == :added do
            Audit.record(
              "conversation.participant_added",
              conversation_audit(conversation, actor, %{"user_id" => user.id})
            )

            notify_changed(conversation.id)
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
  def remove_participant(%User{} = actor, %Conversation{} = conversation, user_id) do
    with {:ok, user_id} <- cast_uuid(user_id),
         {:ok, 1} <- Repo.transaction(fn -> remove_locked(actor, conversation.id, user_id) end) do
      Audit.record("conversation.participant_removed", conversation_audit(conversation, actor, %{"user_id" => user_id}))
      notify_changed(conversation.id)
      :ok
    else
      {:error, :forbidden} -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp remove_locked(actor, conversation_id, user_id) do
    conversation = lock!(conversation_id)

    allowed? =
      conversation.kind == "shared" and user_id != conversation.owner_id and
        actor.id in [conversation.owner_id, user_id]

    if !allowed?, do: Repo.rollback(:forbidden)

    {count, _} =
      Repo.delete_all(
        from participant in Participant,
          where: participant.conversation_id == ^conversation.id and participant.user_id == ^user_id
      )

    if count == 1, do: append!(conversation, %{kind: "system", body: removal_notice(actor, user_id)})
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
  def post_message(%User{} = user, %Conversation{} = conversation, attrs) when is_map(attrs) do
    with {:ok, body} <- message_body(attrs),
         {:ok, client_id} <- client_id(attrs),
         :ok <- rate_limit(user) do
      address_agent? = conversation.kind == "private" or Map.get(attrs, "address_agent", true) != false

      fn -> post_locked(user, conversation.id, body, client_id, address_agent?) end
      |> Repo.transaction()
      |> case do
        {:ok, {message, :created}} ->
          notify_changed(conversation.id)
          {:ok, Repo.preload(message, :author), :created}

        {:ok, {message, :existing}} ->
          {:ok, Repo.preload(message, :author), :existing}

        error ->
          error
      end
    end
  end

  defp post_locked(user, conversation_id, body, client_id, address_agent?) do
    conversation = lock!(conversation_id)

    cond do
      conversation.status != "active" ->
        Repo.rollback(:archived)

      not Access.can_read?(conversation, user) ->
        Repo.rollback(:not_found)

      existing = existing_message(conversation, user, client_id) ->
        {existing, :existing}

      true ->
        message =
          append!(conversation, %{
            kind: "human",
            body: body,
            author_id: user.id,
            author_name: display_name(user),
            client_id: client_id,
            address_agent: address_agent?
          })

        if address_agent?, do: request_run!(conversation, message, user, user)
        {message, :created}
    end
  end

  defp message_body(attrs) do
    case Map.get(attrs, "body") do
      body when is_binary(body) ->
        trimmed = String.trim(body)

        if trimmed != "" and byte_size(body) <= @max_body_bytes,
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
    case RateLimit.hit("conversation_message:#{user_id}", @message_rate_window, @message_rate_limit) do
      {:allow, _attempts} -> :ok
      {:deny, _remaining} -> {:error, :rate_limited}
    end
  end

  defp existing_message(conversation, user, client_id) do
    Repo.one(
      from message in Message,
        where:
          message.conversation_id == ^conversation.id and message.author_id == ^user.id and
            message.client_id == ^client_id
    )
  end

  ## Runs

  @doc "Requests cancellation of an active run. The initiator and the owner may cancel."
  def cancel_run(%User{} = user, %Conversation{} = conversation, run_id) do
    with {:ok, run_id} <- cast_uuid(run_id),
         %Run{} = run <- Repo.get_by(Run, id: run_id, conversation_id: conversation.id),
         true <- run.status in Run.active_statuses(),
         true <- user.id in [run.initiator_id, conversation.owner_id] do
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

  # Inside a transaction holding the conversation lock. Starts a run unless one
  # is already active; the active run's follow-up covers this message.
  defp request_run!(conversation, %Message{} = trigger, initiator, acting_user) do
    cond do
      active_run(conversation) ->
        :pending

      not agent_configured?() ->
        append!(conversation, %{
          kind: "system",
          body:
            "The assistant is not configured on this Atlas server. An administrator can assign an inference profile to conversations."
        })

        :unconfigured

      true ->
        start_run!(conversation, trigger.position, initiator, acting_user)
    end
  end

  @doc false
  def start_run!(conversation, trigger_seq, initiator, acting_user) do
    model_binding_id =
      case Inference.fetch_atlas_role(:conversations) do
        {:ok, binding, _token} -> binding.id
        _ -> nil
      end

    run =
      Repo.insert!(%Run{
        conversation_id: conversation.id,
        initiator_id: initiator && initiator.id,
        acting_user_id: acting_user.id,
        model_binding_id: model_binding_id,
        trigger_seq: trigger_seq,
        status: "queued"
      })

    {:ok, _job} = %{"run_id" => run.id, "resume" => 0} |> RunConversation.new() |> Oban.insert()
    run
  end

  defp cancel_active_runs(conversation, _reason) do
    runs =
      Repo.all(
        from run in Run,
          where: run.conversation_id == ^conversation.id and run.status in ^Run.active_statuses(),
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
  Opens (or appends to) a shared conversation for a monitored signal.

  Required keys: `:owner_id`, `:source_type`, `:source_id`, `:title`, and
  `:summary`. Optional: `:participant_ids` and `:required_scopes`, the access
  the summary itself requires. The owner and every participant must hold those
  scopes; nobody is silently dropped. The assistant acts as the owner, limited
  to what every participant may see, and is re-authorized on every tool call.
  Repeated signals for the same active source append to the same conversation.
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
        conversation =
          case active_signal_conversation(source_type, source_id) do
            nil ->
              {:ok, conversation} =
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
                |> Conversation.create_changeset()
                |> Repo.insert()

              {:ok, _} = insert_participant(conversation, owner.id, "owner")
              :ok = insert_members(conversation, participants)
              lock!(conversation.id)

            existing ->
              lock!(existing.id)
          end

        message = append!(conversation, %{kind: "system", body: summary, address_agent: true})

        if Access.can_read?(conversation, Repo.get(User, conversation.owner_id)) do
          request_run!(conversation, message, nil, Repo.get(User, conversation.owner_id))
        end

        conversation
      end)
      |> case do
        {:ok, conversation} ->
          Audit.record(
            "conversation.signal_received",
            conversation_audit(conversation, nil, %{"source_type" => source_type, "source_id" => source_id})
          )

          notify_changed(conversation.id)
          {:ok, preload_conversation(Repo.get!(Conversation, conversation.id))}

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

  defp active_signal_conversation(source_type, source_id) do
    Repo.one(
      from conversation in Conversation,
        where:
          conversation.origin == "signal" and conversation.status == "active" and
            conversation.source_type == ^source_type and conversation.source_id == ^source_id
    )
  end

  ## Log primitives

  @doc false
  def lock!(conversation_id) do
    Repo.one!(from conversation in Conversation, where: conversation.id == ^conversation_id, lock: "FOR UPDATE")
  end

  @doc false
  # Appends a message, allocating the next sequence number. Must run inside a
  # transaction; the sequence update takes the conversation row lock.
  def append!(%Conversation{id: conversation_id}, attrs) do
    seq = next_seq!(conversation_id)

    Repo.insert!(struct(Message, Map.merge(attrs, %{conversation_id: conversation_id, position: seq, seq: seq})))
  end

  @doc false
  def touch!(%Message{} = message, changes) do
    seq = next_seq!(message.conversation_id)

    message
    |> Ecto.Changeset.change(Map.put(changes, :seq, seq))
    |> Repo.update!()
  end

  defp next_seq!(conversation_id) do
    {1, [seq]} =
      Repo.update_all(
        from(conversation in Conversation, where: conversation.id == ^conversation_id, select: conversation.last_seq),
        inc: [last_seq: 1],
        set: [updated_at: DateTime.utc_now()]
      )

    seq
  end

  ## Helpers

  def display_name(%User{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%User{email: email}), do: email
  def display_name(_user), do: "Someone"

  defp preload_conversation(conversation), do: Repo.preload(conversation, [participants: :user], force: true)

  defp preload_participants(query), do: preload(query, participants: :user)

  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, String.downcase(uuid)}
      :error -> :error
    end
  end

  defp cast_uuid(_value), do: :error

  defp conversation_audit(conversation, actor, metadata \\ %{}) do
    %{
      target_type: "conversation",
      target_id: conversation.id,
      target_label: conversation.kind,
      metadata: Map.merge(%{"kind" => conversation.kind, "origin" => conversation.origin}, metadata)
    }
    |> then(fn attrs -> if actor, do: Map.put(attrs, :actor, actor), else: attrs end)
  end
end
