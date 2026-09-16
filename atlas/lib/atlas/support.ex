defmodule Atlas.Support do
  @moduledoc """
  Shared customer-support conversations received at the Tuist support address.

  Atlas keeps the original inbound email in `inbox_emails`, while this domain
  turns it into a durable, collaborative conversation with an explicit owner
  and lifecycle.
  """

  import Ecto.Query

  alias Atlas.Accounts.EventRouting
  alias Atlas.Audit
  alias Atlas.Mailer
  alias Atlas.Repo
  alias Atlas.Support.Attachments
  alias Atlas.Support.Email
  alias Atlas.Support.Message
  alias Atlas.Support.Thread
  alias Atlas.Support.Workers.DeliverChatEmailVerification
  alias Atlas.Support.Workers.DeliverReply
  alias Atlas.Support.Workers.PostNotification
  alias Atlas.Users
  alias AtlasWeb.Endpoint

  require Logger

  @default_page_size 50
  @thread_statuses ~w(open waiting resolved)
  @chat_email_verification_salt "support chat email verification"
  @chat_email_verification_max_age 60 * 60 * 24 * 7

  def support_address do
    :atlas
    |> Application.get_env(:support, [])
    |> Keyword.fetch!(:from_email)
    |> normalize_email()
  end

  def support_address?(email) when is_map(email) do
    recipient_emails(email)
    |> Enum.any?(&(&1 == support_address()))
  end

  def support_address?(_email), do: false

  def list_threads(opts \\ []) do
    status = Keyword.get(opts, :status)
    owner_id = Keyword.get(opts, :owner_id)
    query = Keyword.get(opts, :query)
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    page = Keyword.get(opts, :page, 1)

    threads_query =
      Thread
      |> maybe_filter_status(status)
      |> maybe_filter_owner(owner_id)
      |> maybe_search(query)
      |> order_by([thread], desc: thread.last_message_at, desc: thread.id)
      |> preload([:account, :owner])

    Flop.run(threads_query, %Flop{page: max(page, 1), page_size: max(page_size, 1)}, for: Thread)
  end

  def list_thread_counts(owner_id \\ nil) do
    Thread
    |> maybe_filter_owner(owner_id)
    |> group_by([thread], thread.status)
    |> select([thread], {thread.status, count(thread.id)})
    |> Repo.all()
    |> Map.new()
    |> then(fn counts -> Map.merge(%{"open" => 0, "waiting" => 0, "resolved" => 0}, counts) end)
  end

  def get_thread(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        messages_query =
          from(message in Message, order_by: [asc: message.occurred_at, asc: message.id], preload: [:author])

        Thread
        |> Repo.get(id)
        |> case do
          nil -> nil
          thread -> Repo.preload(thread, [:account, :owner, messages: messages_query])
        end

      :error ->
        nil
    end
  end

  def get_thread(_id), do: nil

  def get_inbound_message(message_id) when is_binary(message_id) do
    case Ecto.UUID.cast(message_id) do
      {:ok, message_id} ->
        Message
        |> where([message], message.id == ^message_id and message.kind == "inbound")
        |> preload(:inbox_email)
        |> Repo.one()

      :error ->
        nil
    end
  end

  def get_inbound_message(_message_id), do: nil

  def get_message(message_id) when is_binary(message_id) do
    case Ecto.UUID.cast(message_id) do
      {:ok, message_id} ->
        Message
        |> where([message], message.id == ^message_id)
        |> preload(:inbox_email)
        |> Repo.one()

      :error ->
        nil
    end
  end

  def get_message(_message_id), do: nil

  @doc """
  Creates or extends a support thread from an already parsed Cloudflare email.

  This deliberately does not use the inbox sender allowlist: `contact@tuist.dev`
  must accept a first message from any customer. The signed Cloudflare relay is
  still the ingress trust boundary.
  """
  def ingest_inbound(email, inbox_email_id) when is_map(email) and is_binary(inbox_email_id) do
    Repo.transaction(fn ->
      case existing_inbound_message(email, inbox_email_id) do
        %Message{} = message ->
          thread = get_thread!(message.thread_id)
          %{thread: thread, message: message, duplicate?: true}

        nil ->
          inbound = inbound_sender(email)
          thread = find_thread(email, inbound.email) || create_thread!(email, inbound)
          message = create_inbound_message!(thread, email, inbound, inbox_email_id)
          thread = refresh_thread_after_inbound!(thread, email, inbound)

          %{thread: thread, message: message, duplicate?: false}
      end
    end)
    |> case do
      {:ok, %{thread: thread, message: message, duplicate?: duplicate?}} ->
        if !duplicate? do
          audit_inbound(thread, message)
          enqueue_notification(:inbound_received, thread.id, message_id: message.id)
        end

        {:ok, %{thread: thread, message: message}}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Records a new customer conversation initiated through the embedded chat.

  A browser starts a fresh conversation rather than looking one up by email.
  The opaque conversation token issued by the web interface is required to
  append later chat messages, so knowing a customer's email cannot reveal or
  join an earlier conversation.
  """
  def receive_chat(attrs) when is_map(attrs) do
    with {:ok, chat} <- chat_attrs(attrs) do
      Repo.transaction(fn ->
        thread = create_chat_thread!(chat)
        message = create_chat_message!(thread, chat)
        %{thread: thread, message: message}
      end)
      |> finish_chat()
    end
  end

  @doc """
  Appends a customer message to an existing embedded-chat conversation.
  """
  def receive_chat(%Thread{} = thread, attrs) when is_map(attrs) do
    with {:ok, chat} <- chat_attrs(attrs, thread) do
      Repo.transaction(fn ->
        thread = lock_thread!(thread.id)
        message = create_chat_message!(thread, chat)

        thread =
          thread
          |> Thread.inbound_changeset(%{
            customer_name: thread.customer_name || chat.customer_name,
            customer_email: thread.customer_email,
            subject: thread.subject,
            status: "open",
            last_message_at: chat.occurred_at,
            last_inbound_at: chat.occurred_at,
            resolved_at: nil
          })
          |> Repo.update!()

        %{thread: thread, message: message}
      end)
      |> finish_chat()
    end
  end

  def receive_chat(_thread, _attrs), do: {:error, :not_found}

  @doc """
  Confirms that a chat visitor controls the email address on their conversation.
  """
  def confirm_chat_email(token) when is_binary(token) do
    with {:ok, %{"thread_id" => thread_id, "email" => email}} <-
           Phoenix.Token.verify(Endpoint, @chat_email_verification_salt, token,
             max_age: @chat_email_verification_max_age
           ),
         %Thread{} = thread <- get_thread(thread_id),
         true <- thread.customer_email == email,
         {:ok, {thread, confirmed?}} <- confirm_chat_email_thread(thread) do
      if confirmed?, do: audit_chat_email_verified(thread)
      broadcast_thread_update(thread.id)
      {:ok, thread}
    else
      {:error, reason} -> {:error, reason}
      _error -> {:error, :invalid_or_expired_token}
    end
  end

  def confirm_chat_email(_token), do: {:error, :invalid_or_expired_token}

  def chat_email_verification_url(%Thread{} = thread) do
    token =
      Phoenix.Token.sign(Endpoint, @chat_email_verification_salt, %{
        "thread_id" => thread.id,
        "email" => thread.customer_email
      })

    Endpoint.url() <> "/support/chat/verify/#{token}"
  end

  def reply(%Thread{} = thread, attrs, actor) when is_map(attrs) do
    now = now()
    body = attrs |> value(:body) |> normalize_text()
    reply_all? = value(attrs, :reply_all) in [true, "true", "on"]
    attachments = attrs |> value(:attachments) |> List.wrap()

    cond do
      is_nil(body) ->
        {:error, :body_required}

      is_nil(actor) ->
        {:error, :actor_required}

      unverified_chat?(thread) and attachments != [] ->
        {:error, :chat_reply_attachments_unsupported}

      true ->
        queue_reply(thread, body, reply_all?, attachments, actor, now)
    end
  end

  def reply(thread_id, attrs, actor) when is_binary(thread_id) do
    case get_thread(thread_id) do
      nil -> {:error, :not_found}
      thread -> reply(thread, attrs, actor)
    end
  end

  defp queue_reply(thread, body, reply_all?, attachments, actor, now) do
    with {:ok, attachment_metadata} <- Attachments.store(thread, attachments) do
      case queue_reply_transaction(thread, body, reply_all?, attachment_metadata, actor, now) do
        {:ok, _result} = result ->
          finish_reply(result, actor)

        {:error, reason} ->
          Attachments.delete_all(attachment_metadata)
          {:error, reason}
      end
    end
  end

  defp queue_reply_transaction(thread, body, reply_all?, attachment_metadata, actor, now) do
    Repo.transaction(fn ->
      thread = lock_thread!(thread.id)
      delivery_channel = reply_delivery_channel_for_thread(thread)
      previous_message = latest_email_message(thread.id)

      message =
        create_outbound_reply!(
          thread,
          previous_message,
          body,
          reply_all?,
          attachment_metadata,
          delivery_channel,
          actor,
          now
        )

      thread =
        thread
        |> Thread.outbound_changeset(%{status: "waiting", last_message_at: now, resolved_at: nil})
        |> Repo.update!()

      finalize_reply!(message, thread, delivery_channel, now)
    end)
  end

  defp create_outbound_reply!(
         thread,
         previous_message,
         body,
         reply_all?,
         attachment_metadata,
         delivery_channel,
         actor,
         now
       ) do
    {to_emails, cc_emails} = reply_recipients(thread, previous_message, reply_all?)
    references = reply_references(thread.id, previous_message)

    %Message{thread_id: thread.id, author_id: actor.id}
    |> Message.outbound_changeset(%{
      kind: "outbound",
      message_id: generated_message_id(),
      in_reply_to: List.last(references),
      references: references,
      sender_name: support_sender_name(),
      sender_email: support_address(),
      to_emails: to_emails,
      cc_emails: cc_emails,
      body: body,
      delivery_status: "queued",
      occurred_at: now,
      metadata: %{"attachments" => attachment_metadata, "delivery_channel" => delivery_channel}
    })
    |> Repo.insert!()
  end

  defp finalize_reply!(message, thread, "chat", now) do
    message =
      message
      |> Message.delivery_changeset(%{delivery_status: "delivered", delivered_at: now})
      |> Repo.update!()

    %{thread: thread, message: message}
  end

  defp finalize_reply!(message, thread, "email", _now), do: enqueue_reply!(message, thread)

  defp enqueue_reply!(message, thread) do
    case DeliverReply.enqueue(message.id) do
      {:ok, _job} -> %{thread: thread, message: message}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp finish_reply({:ok, %{thread: updated_thread, message: message}}, actor) do
    thread = get_thread(updated_thread.id)
    message = Enum.find(thread.messages, &(&1.id == message.id))

    if reply_delivery_channel_for_message(message) == "chat" do
      audit_reply_sent_in_chat(thread, message, actor)

      enqueue_notification(:reply_delivered, thread.id,
        message_id: message.id,
        actor_id: actor.id
      )
    else
      audit_reply_queued(thread, message, actor)
    end

    broadcast_thread_update(thread.id)
    {:ok, %{thread: thread, message: message}}
  end

  defp finish_chat({:ok, %{thread: updated_thread, message: message}}) do
    thread = get_thread(updated_thread.id)
    message = Enum.find(thread.messages, &(&1.id == message.id))
    audit_chat(thread, message)
    enqueue_notification(:chat_received, thread.id, message_id: message.id)
    enqueue_chat_email_verification(thread)
    broadcast_thread_update(thread.id)
    {:ok, %{thread: thread, message: message}}
  end

  defp finish_chat({:error, reason}), do: {:error, reason}

  def add_note(%Thread{} = thread, attrs, actor) when is_map(attrs) do
    body = attrs |> value(:body) |> normalize_text()

    cond do
      is_nil(body) ->
        {:error, :body_required}

      is_nil(actor) ->
        {:error, :actor_required}

      true ->
        %Message{thread_id: thread.id, author_id: actor.id}
        |> Message.note_changeset(%{kind: "note", body: body, occurred_at: now()})
        |> Repo.insert()
        |> case do
          {:ok, message} ->
            audit_note(thread, message, actor)
            enqueue_notification(:note_added, thread.id, message_id: message.id, actor_id: actor.id)
            {:ok, Repo.preload(message, :author)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def add_note(thread_id, attrs, actor) when is_binary(thread_id) do
    case get_thread(thread_id) do
      nil -> {:error, :not_found}
      thread -> add_note(thread, attrs, actor)
    end
  end

  def set_status(%Thread{} = thread, status, actor) when status in @thread_statuses do
    resolved_at = if status == "resolved", do: now()

    thread
    |> Thread.status_changeset(%{status: status, resolved_at: resolved_at})
    |> Ecto.Changeset.put_change(:resolved_at, resolved_at)
    |> Repo.update()
    |> tap(fn
      {:ok, updated_thread} ->
        audit_status(updated_thread, actor)

        enqueue_notification(:status_changed, updated_thread.id,
          actor_id: actor && actor.id,
          status: updated_thread.status
        )

      _result ->
        :ok
    end)
  end

  def set_status(thread_id, status, actor) when is_binary(thread_id) do
    case get_thread(thread_id) do
      nil -> {:error, :not_found}
      thread -> set_status(thread, status, actor)
    end
  end

  def set_status(_thread, _status, _actor), do: {:error, :invalid_status}

  def assign(%Thread{} = thread, user_id, actor) when is_binary(user_id) do
    with %{} = owner <- Users.get_user(user_id) || {:error, :owner_not_found} do
      thread
      |> Thread.owner_changeset(%{owner_id: owner.id})
      |> Repo.update()
      |> tap(fn
        {:ok, updated_thread} ->
          audit_assignment(updated_thread, actor)

          enqueue_notification(:assigned, updated_thread.id,
            actor_id: actor && actor.id,
            assignee_id: updated_thread.owner_id
          )

        _result ->
          :ok
      end)
    end
  end

  def assign(thread_id, user_id, actor) when is_binary(thread_id) and is_binary(user_id) do
    case get_thread(thread_id) do
      nil -> {:error, :not_found}
      thread -> assign(thread, user_id, actor)
    end
  end

  def assign(_thread, _user_id, _actor), do: {:error, :owner_not_found}

  def deliver_reply(message_id) when is_binary(message_id) do
    case claim_delivery(message_id) do
      {:cancel, :not_found} ->
        {:cancel, :not_found}

      :already_claimed ->
        :ok

      {:ok, %Message{} = message} ->
        deliver(message)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def deliver_chat_email_verification(thread_id) when is_binary(thread_id) do
    case get_thread(thread_id) do
      %Thread{} = thread ->
        if unverified_chat?(thread) do
          with {:ok, _response} <-
                 thread
                 |> Email.chat_email_verification(chat_email_verification_url(thread))
                 |> Mailer.deliver() do
            audit_chat_email_verification_sent(thread)
            :ok
          end
        else
          :ok
        end

      nil ->
        {:cancel, :not_found}
    end
  end

  defp deliver(message) do
    with {:ok, email} <- Email.reply(message.thread, message),
         {:ok, response} <- Mailer.deliver(email) do
      message
      |> Message.delivery_changeset(%{
        delivery_status: "delivered",
        provider_message_id: provider_message_id(response),
        delivery_error: nil,
        delivered_at: now()
      })
      |> Repo.update()
      |> case do
        {:ok, delivered_message} ->
          audit_reply_delivered(delivered_message.thread, delivered_message)

          enqueue_notification(:reply_delivered, delivered_message.thread_id,
            message_id: delivered_message.id,
            actor_id: delivered_message.author_id
          )

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} ->
        message
        |> Message.delivery_changeset(%{delivery_status: "failed", delivery_error: inspect(reason)})
        |> Repo.update()

        audit_reply_failed(message.thread, message, reason)
        {:error, reason}
    end
  end

  defp claim_delivery(id) do
    Repo.transaction(fn ->
      message =
        Message
        |> where([message], message.id == ^id and message.kind == "outbound")
        |> lock("FOR UPDATE")
        |> Repo.one()

      case message do
        nil ->
          Repo.rollback(:not_found)

        %Message{delivery_status: status} when status in ["queued", "failed"] ->
          message
          |> Message.delivery_changeset(%{delivery_status: "sending", delivery_error: nil})
          |> Repo.update!()
          |> Repo.preload(:thread)

        %Message{} ->
          :already_claimed
      end
    end)
    |> case do
      {:ok, :already_claimed} -> :already_claimed
      {:ok, message} -> {:ok, message}
      {:error, :not_found} -> {:cancel, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_thread(email, customer_email) do
    message_ids = email_threading_ids(email)

    thread =
      if message_ids != [] do
        Message
        |> join(:inner, [message], thread in Thread, on: thread.id == message.thread_id)
        |> where([message, _thread], message.message_id in ^message_ids)
        |> where([_message, thread], fragment("lower(?)", thread.customer_email) == ^customer_email)
        |> order_by([message], desc: message.occurred_at, desc: message.id)
        |> limit(1)
        |> select([_message, thread], thread)
        |> Repo.one()
      end

    # Only message threading headers identify a prior conversation reliably.
    # Reusing a thread merely because a customer used the same subject could
    # merge two unrelated requests months apart.
    if message_ids != [], do: thread
  end

  defp existing_inbound_message(email, inbox_email_id) do
    Message
    |> maybe_match_message_id(inbox_email_id, email.message_id)
    |> Repo.one()
  end

  defp maybe_match_message_id(query, inbox_email_id, nil),
    do: where(query, [message], message.inbox_email_id == ^inbox_email_id)

  defp maybe_match_message_id(query, inbox_email_id, message_id) do
    normalized_message_id = normalize_message_id(message_id)

    if normalized_message_id do
      where(query, [message], message.inbox_email_id == ^inbox_email_id or message.message_id == ^normalized_message_id)
    else
      query
    end
  end

  defp create_thread!(email, inbound) do
    account = EventRouting.find_account([inbound.email])

    %Thread{account_id: account && account.account.id}
    |> Thread.inbound_changeset(%{
      customer_name: inbound.name,
      customer_email: inbound.email,
      subject: email.subject || "Tuist support",
      status: "open",
      last_message_at: email.occurred_at,
      last_inbound_at: email.occurred_at,
      resolved_at: nil
    })
    |> Repo.insert!()
  end

  defp create_chat_thread!(chat) do
    %Thread{}
    |> Thread.inbound_changeset(%{
      customer_name: chat.customer_name,
      customer_email: chat.customer_email,
      subject: "Chat with Tuist Support",
      status: "open",
      last_message_at: chat.occurred_at,
      last_inbound_at: chat.occurred_at,
      resolved_at: nil,
      metadata: chat_metadata(chat)
    })
    |> Repo.insert!()
  end

  defp refresh_thread_after_inbound!(thread, email, inbound) do
    thread
    |> Thread.inbound_changeset(%{
      customer_name: thread.customer_name || inbound.name,
      customer_email: thread.customer_email || inbound.email,
      subject: thread.subject || email.subject,
      status: "open",
      last_message_at: email.occurred_at,
      last_inbound_at: email.occurred_at,
      resolved_at: nil
    })
    |> Repo.update!()
  end

  defp create_inbound_message!(thread, email, inbound, inbox_email_id) do
    %Message{thread_id: thread.id}
    |> Message.inbound_changeset(%{
      inbox_email_id: inbox_email_id,
      kind: "inbound",
      message_id: email.message_id,
      in_reply_to: email.in_reply_to,
      references: email.references,
      sender_name: inbound.name,
      sender_email: inbound.email,
      to_emails: participant_emails(email.to),
      cc_emails: participant_emails(email.cc),
      body: email.text_body || "(No readable email body.)",
      occurred_at: email.occurred_at,
      metadata: %{"attachments" => attachment_metadata(email.attachments)}
    })
    |> Repo.insert!()
  end

  defp create_chat_message!(thread, chat) do
    %Message{thread_id: thread.id}
    |> Message.chat_changeset(%{
      kind: "chat",
      sender_name: chat.customer_name,
      sender_email: chat.customer_email,
      to_emails: [],
      cc_emails: [],
      body: chat.body,
      occurred_at: chat.occurred_at,
      metadata: chat_metadata(chat)
    })
    |> Repo.insert!()
  end

  defp inbound_sender(email) do
    participant = List.first(email.from) || %{}

    %{
      name: Map.get(participant, :name),
      email: normalize_email(Map.get(participant, :email) || Map.get(email.envelope, "from")) || "unknown@invalid"
    }
  end

  defp recipient_emails(email) do
    (participant_emails(Map.get(email, :to, [])) ++
       participant_emails(Map.get(email, :cc, [])) ++
       [Map.get(Map.get(email, :envelope, %{}), "to")])
    |> Enum.map(&normalize_email/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp participant_emails(participants) do
    participants
    |> List.wrap()
    |> Enum.map(&Map.get(&1, :email))
    |> Enum.map(&normalize_email/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp attachment_metadata(attachments) do
    Enum.map(attachments, fn attachment ->
      %{
        "filename" => attachment.filename,
        "content_type" => attachment.content_type,
        "byte_size" => attachment.byte_size,
        "content_id" => attachment.content_id,
        "checksum_sha256" => attachment.checksum_sha256
      }
    end)
  end

  defp email_threading_ids(email) do
    [email.in_reply_to | email.references]
    |> List.flatten()
    |> Enum.map(&normalize_message_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp reply_recipients(thread, previous_message, reply_all?) do
    base = [thread.customer_email]

    cc_emails =
      if reply_all? and previous_message do
        (previous_message.cc_emails ++ previous_message.to_emails)
        |> Enum.reject(&(&1 == support_address() or &1 == thread.customer_email))
        |> Enum.uniq()
      else
        []
      end

    {base, cc_emails}
  end

  defp latest_email_message(thread_id) do
    Message
    |> where([message], message.thread_id == ^thread_id and message.kind in ["inbound", "outbound"])
    |> order_by([message], desc: message.occurred_at, desc: message.id)
    |> limit(1)
    |> Repo.one()
  end

  defp reply_references(thread_id, previous_message) do
    message_ids =
      Message
      |> where([message], message.thread_id == ^thread_id and message.kind in ["inbound", "outbound"])
      |> where([message], not is_nil(message.message_id))
      |> order_by([message], asc: message.occurred_at, asc: message.id)
      |> select([message], message.message_id)
      |> Repo.all()

    message_ids =
      if previous_message && previous_message.message_id,
        do: message_ids ++ [previous_message.message_id],
        else: message_ids

    message_ids
    |> Enum.uniq()
    |> Enum.take(-20)
  end

  defp generated_message_id do
    "support-#{Atlas.UUIDv7.generate()}@atlas.tuist.dev"
  end

  defp support_sender_name do
    :atlas
    |> Application.get_env(:support, [])
    |> Keyword.fetch!(:from_name)
  end

  defp reply_delivery_channel_for_thread(thread) do
    if unverified_chat?(thread), do: "chat", else: "email"
  end

  defp reply_delivery_channel_for_message(message) do
    Map.get(message.metadata || %{}, "delivery_channel", "email")
  end

  defp audit_inbound(thread, message) do
    Audit.record("support.thread_received", %{
      interface: "worker",
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "message_id" => message.id,
        "sender_email" => message.sender_email
      }
    })
  end

  defp audit_chat(thread, message) do
    Audit.record("support.chat_received", %{
      interface: "api",
      actor_email: message.sender_email,
      actor_name: message.sender_name,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "channel" => "chat",
        "email_verified" => chat_email_verified?(thread),
        "message_id" => message.id,
        "source_url" => Map.get(message.metadata, "source_url")
      }
    })
  end

  defp audit_chat_email_verification_sent(thread) do
    Audit.record("support.chat_email_verification_sent", %{
      interface: "worker",
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{"dashboard_path" => "/support/#{thread.id}"}
    })
  end

  defp audit_chat_email_verified(thread) do
    Audit.record("support.chat_email_verified", %{
      interface: "api",
      actor_email: thread.customer_email,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "account_id" => thread.account_id
      }
    })
  end

  defp audit_reply_queued(thread, message, actor) do
    Audit.record("support.reply_queued", %{
      actor: actor,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "message_id" => message.id,
        "recipients" => message.to_emails
      }
    })
  end

  defp audit_reply_sent_in_chat(thread, message, actor) do
    Audit.record("support.reply_sent_in_chat", %{
      actor: actor,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "message_id" => message.id,
        "recipients" => message.to_emails
      }
    })
  end

  defp audit_reply_delivered(thread, message) do
    Audit.record("support.reply_delivered", %{
      interface: "worker",
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "message_id" => message.id,
        "provider_message_id" => message.provider_message_id
      }
    })
  end

  defp audit_reply_failed(thread, message, reason) do
    Audit.record("support.reply_failed", %{
      interface: "worker",
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{
        "dashboard_path" => "/support/#{thread.id}",
        "message_id" => message.id,
        "reason" => inspect(reason)
      }
    })
  end

  defp audit_note(thread, message, actor) do
    Audit.record("support.note_added", %{
      actor: actor,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{"dashboard_path" => "/support/#{thread.id}", "message_id" => message.id}
    })
  end

  defp audit_status(thread, actor) do
    Audit.record("support.status_changed", %{
      actor: actor,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{"dashboard_path" => "/support/#{thread.id}", "status" => thread.status}
    })
  end

  defp audit_assignment(thread, actor) do
    Audit.record("support.assigned", %{
      actor: actor,
      target_type: "support_thread",
      target_id: thread.id,
      target_label: thread.subject,
      metadata: %{"dashboard_path" => "/support/#{thread.id}", "owner_id" => thread.owner_id}
    })
  end

  defp enqueue_notification(event, thread_id, opts) do
    case PostNotification.enqueue(event, thread_id, opts) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not enqueue #{event} support notification for conversation #{thread_id}: #{inspect(reason)}"
        )
    end
  end

  defp enqueue_chat_email_verification(thread) do
    case DeliverChatEmailVerification.enqueue(thread.id) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not enqueue chat email verification for conversation #{thread.id}: #{inspect(reason)}")
    end
  end

  defp broadcast_thread_update(thread_id) do
    Phoenix.PubSub.broadcast(Atlas.PubSub, "support:thread:#{thread_id}", {:support_thread_updated, thread_id})
  end

  defp get_thread!(id), do: Repo.get!(Thread, id)
  defp lock_thread!(id), do: Thread |> where([thread], thread.id == ^id) |> lock("FOR UPDATE") |> Repo.one!()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_text(_value), do: nil

  defp chat_attrs(attrs, thread \\ nil) do
    customer_name = attrs |> value(:name) |> normalize_optional_text()
    customer_email = attrs |> value(:email) |> normalize_email()
    body = attrs |> value(:body) |> normalize_text()
    source_url = attrs |> value(:source_url) |> normalize_source_url()

    with {:ok, customer_email} <- chat_email(customer_email),
         :ok <- matching_customer?(thread, customer_email),
         {:ok, body} <- chat_body(body),
         :ok <- valid_customer_name?(customer_name) do
      {:ok,
       %{
         customer_name: customer_name,
         customer_email: customer_email,
         body: body,
         source_url: source_url,
         occurred_at: now()
       }}
    end
  end

  defp chat_email(nil), do: {:error, :email_required}

  defp chat_email(email) do
    if valid_customer_email?(email), do: {:ok, email}, else: {:error, :email_invalid}
  end

  defp matching_customer?(nil, _customer_email), do: :ok
  defp matching_customer?(%Thread{customer_email: customer_email}, customer_email), do: :ok
  defp matching_customer?(%Thread{}, _customer_email), do: {:error, :customer_mismatch}

  defp chat_body(nil), do: {:error, :body_required}

  defp chat_body(body) do
    if String.length(body) <= 10_000, do: {:ok, body}, else: {:error, :body_too_long}
  end

  defp valid_customer_name?(nil), do: :ok

  defp valid_customer_name?(name) do
    if String.length(name) <= 255, do: :ok, else: {:error, :name_too_long}
  end

  defp chat_metadata(chat) do
    %{"channel" => "chat", "email_verified" => false}
    |> maybe_put("source_url", chat.source_url)
  end

  defp confirm_chat_email_thread(thread) do
    Repo.transaction(fn ->
      thread = lock_thread!(thread.id)

      cond do
        !chat_thread?(thread) ->
          Repo.rollback(:not_found)

        chat_email_verified?(thread) ->
          {thread, false}

        true ->
          account = EventRouting.find_account([thread.customer_email])
          metadata = Map.put(thread.metadata || %{}, "email_verified", true)

          verified_thread =
            thread
            |> Thread.inbound_changeset(%{metadata: metadata})
            |> Ecto.Changeset.put_change(:account_id, account && account.account.id)
            |> Repo.update!()

          {verified_thread, true}
      end
    end)
  end

  defp chat_thread?(%Thread{metadata: metadata}), do: Map.get(metadata || %{}, "channel") == "chat"
  defp chat_email_verified?(thread), do: Map.get(thread.metadata || %{}, "email_verified") == true
  defp unverified_chat?(thread), do: chat_thread?(thread) and !chat_email_verified?(thread)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_optional_text(_value), do: nil

  defp normalize_source_url(value) when is_binary(value) do
    value = String.trim(value)

    with true <- value != "",
         true <- String.length(value) <= 2_000,
         %URI{scheme: scheme, host: host} <- URI.parse(value),
         true <- scheme in ["http", "https"],
         true <- is_binary(host) and host != "" do
      value
    else
      _invalid -> nil
    end
  end

  defp normalize_source_url(_value), do: nil

  defp valid_customer_email?(email) do
    String.length(email) <= 254 and String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end

  defp normalize_email(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> String.downcase(value)
    end
  end

  defp normalize_email(_value), do: nil

  defp normalize_message_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> case do
      "" -> nil
      message_id -> message_id
    end
  end

  defp normalize_message_id(_value), do: nil

  defp maybe_filter_status(query, status) when status in @thread_statuses,
    do: where(query, [thread], thread.status == ^status)

  defp maybe_filter_status(query, _status), do: query

  defp maybe_filter_owner(query, owner_id) when is_binary(owner_id),
    do: where(query, [thread], thread.owner_id == ^owner_id)

  defp maybe_filter_owner(query, _owner_id), do: query

  defp maybe_search(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      value ->
        where(query, [thread], ilike(thread.customer_email, ^"%#{value}%") or ilike(thread.subject, ^"%#{value}%"))
    end
  end

  defp maybe_search(query, _value), do: query

  defp provider_message_id(%{id: id}) when is_binary(id), do: id
  defp provider_message_id(%{"id" => id}) when is_binary(id), do: id
  defp provider_message_id(_response), do: nil
end
