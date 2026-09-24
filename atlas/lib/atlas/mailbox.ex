defmodule Atlas.Mailbox do
  @moduledoc """
  Email received at and sent from the support address. The inbox reads inbound
  support messages; the outbox reads GTM deliveries and emailed support replies.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.GTM.Audience
  alias Atlas.GTM.Broadcast
  alias Atlas.GTM.Delivery
  alias Atlas.Repo
  alias Atlas.Support
  alias Atlas.Support.Message

  @default_page_size 25
  @max_page_size 100

  @support_reply_kind "support_reply"
  @outbox_kinds Delivery.kinds() ++ [@support_reply_kind]
  @outbox_statuses ~w(queued sent failed skipped)

  def address, do: Support.support_address()

  def outbox_kinds, do: @outbox_kinds
  def outbox_statuses, do: @outbox_statuses

  def list_inbox(opts \\ []) do
    inbox_query()
    |> search_inbox(Keyword.get(opts, :query))
    |> order_by([entry: entry], desc: entry.received_at, desc: entry.id)
    |> paginate(opts)
    |> then(fn {entries, metadata} -> {put_accounts(entries), metadata} end)
  end

  def list_outbox(opts \\ []) do
    outbox_query()
    |> search_outbox(Keyword.get(opts, :query))
    |> filter_outbox(:kind, Keyword.get(opts, :kind))
    |> filter_outbox(:status, Keyword.get(opts, :status))
    |> order_by([entry: entry], desc: entry.queued_at, desc: entry.id)
    |> paginate(opts)
    |> then(fn {entries, metadata} ->
      {entries |> Enum.map(&prepare_outbox_entry/1) |> put_accounts(), metadata}
    end)
  end

  def get_sent_email(id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = entry <- outbox_query() |> where([entry: entry], entry.id == ^id) |> Repo.one() do
      entry
      |> prepare_outbox_entry()
      |> put_content()
      |> List.wrap()
      |> put_accounts()
      |> List.first()
    else
      _missing -> nil
    end
  end

  def get_sent_email(_id), do: nil

  defp inbox_query do
    received =
      from(message in Message,
        join: thread in assoc(message, :thread),
        left_join: inbox_email in assoc(message, :inbox_email),
        where: message.kind == "inbound",
        select: %{
          id: message.id,
          thread_id: message.thread_id,
          thread_status: thread.status,
          account_id: fragment("?::text", thread.account_id),
          from_name: message.sender_name,
          from_email: message.sender_email,
          to_emails: message.to_emails,
          cc_emails: message.cc_emails,
          subject: coalesce(fragment("?->>'subject'", message.metadata), thread.subject),
          received_at: coalesce(inbox_email.received_at, message.occurred_at)
        }
      )

    from(entry in subquery(received), as: :entry)
  end

  defp outbox_query do
    from(entry in subquery(union_all(deliveries_query(), ^support_replies_query())), as: :entry)
  end

  # The first query of a union decides how every column is loaded.
  defp deliveries_query do
    defaults = Application.get_env(:atlas, :gtm_email, [])
    default_from_name = defaults[:from_name]
    default_from_email = defaults[:from_email]

    from(delivery in Delivery,
      left_join: broadcast in assoc(delivery, :broadcast),
      select: %{
        id: delivery.id,
        kind: delivery.kind,
        from_name:
          coalesce(
            coalesce(broadcast.from_name, fragment("?->>'from_name'", delivery.metadata)),
            ^default_from_name
          ),
        from_email:
          coalesce(
            coalesce(broadcast.from_email, fragment("?->>'from_email'", delivery.metadata)),
            ^default_from_email
          ),
        recipient_name: delivery.recipient_name,
        to_emails: fragment("ARRAY[?]::varchar[]", delivery.recipient_email),
        cc_emails: fragment("ARRAY[]::varchar[]"),
        subject: delivery.subject,
        status:
          fragment(
            "CASE ? WHEN 'pending' THEN 'queued' WHEN 'delivered' THEN 'sent' ELSE ? END",
            delivery.status,
            delivery.status
          ),
        error: delivery.error,
        provider_message_id: delivery.provider_message_id,
        queued_at: type(delivery.inserted_at, :utc_datetime),
        delivered_at: delivery.delivered_at,
        account_id: fragment("?->>'account_id'", delivery.metadata),
        thread_id: fragment("NULL::text"),
        broadcast_id: fragment("?::text", delivery.broadcast_id),
        audience_id: fragment("?::text", coalesce(delivery.audience_id, broadcast.audience_id))
      }
    )
  end

  defp support_replies_query do
    from(message in Message,
      join: thread in assoc(message, :thread),
      where: message.kind == "outbound",
      where: coalesce(fragment("?->>'delivery_channel'", message.metadata), "email") == "email",
      select: %{
        id: message.id,
        kind: type(^@support_reply_kind, :string),
        from_name: message.sender_name,
        from_email: message.sender_email,
        recipient_name: fragment("NULL::varchar"),
        to_emails: message.to_emails,
        cc_emails: message.cc_emails,
        subject: thread.subject,
        status:
          fragment(
            "CASE WHEN ? IN ('queued', 'sending') THEN 'queued' WHEN ? = 'delivered' THEN 'sent' ELSE ? END",
            message.delivery_status,
            message.delivery_status,
            message.delivery_status
          ),
        error: message.delivery_error,
        provider_message_id: message.provider_message_id,
        queued_at: message.occurred_at,
        delivered_at: message.delivered_at,
        account_id: fragment("?::text", thread.account_id),
        thread_id: fragment("?::text", message.thread_id),
        broadcast_id: fragment("NULL::text"),
        audience_id: fragment("NULL::text")
      }
    )
  end

  defp search_inbox(query, value) do
    case search_pattern(value) do
      nil ->
        query

      pattern ->
        where(
          query,
          [entry: entry],
          ilike(entry.subject, ^pattern) or ilike(entry.from_email, ^pattern) or ilike(entry.from_name, ^pattern)
        )
    end
  end

  defp search_outbox(query, value) do
    case search_pattern(value) do
      nil ->
        query

      pattern ->
        where(
          query,
          [entry: entry],
          ilike(entry.subject, ^pattern) or ilike(entry.from_email, ^pattern) or
            ilike(entry.recipient_name, ^pattern) or
            fragment("array_to_string(?, ' ') ILIKE ?", entry.to_emails, ^pattern) or
            fragment("array_to_string(?, ' ') ILIKE ?", entry.cc_emails, ^pattern)
        )
    end
  end

  defp search_pattern(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> "%#{value}%"
    end
  end

  defp search_pattern(_value), do: nil

  defp filter_outbox(query, field, filter) do
    case option_filter(filter) do
      nil -> query
      {:==, value} -> where(query, [entry: entry], field(entry, ^field) == ^value)
      {:!=, value} -> where(query, [entry: entry], field(entry, ^field) != ^value)
    end
  end

  defp option_filter({operator, value}) when operator in [:==, :!=] and is_binary(value) and value != "",
    do: {operator, value}

  defp option_filter(value) when is_binary(value) and value != "", do: {:==, value}
  defp option_filter(_filter), do: nil

  defp paginate(query, opts) do
    page = normalized_page(Keyword.get(opts, :page))
    size = page_size(Keyword.get(opts, :page_size))

    {entries, metadata} = Flop.run(query, %Flop{limit: size, offset: (page - 1) * size}, repo: Repo)
    total_count = metadata.total_count || 0

    {entries,
     %{
       current_page: page,
       page_size: size,
       total_count: total_count,
       total_pages: max(ceil(total_count / size), 1)
     }}
  end

  defp normalized_page(page) when is_integer(page) and page > 0, do: page
  defp normalized_page(_page), do: 1

  defp page_size(value) when is_integer(value) and value > 0, do: min(value, @max_page_size)
  defp page_size(_value), do: @default_page_size

  defp prepare_outbox_entry(%{kind: @support_reply_kind} = entry) do
    %{entry | subject: Support.Email.reply_subject(entry.subject)}
  end

  defp prepare_outbox_entry(entry), do: entry

  defp put_content(%{kind: @support_reply_kind} = entry) do
    message = Repo.get!(Message, entry.id)

    Map.merge(entry, %{
      body_markdown: message.body,
      template: nil,
      reply_to_email: message.sender_email,
      audience_name: nil
    })
  end

  defp put_content(entry) do
    delivery = Delivery |> Repo.get!(entry.id) |> Repo.preload([:audience, broadcast: :audience])
    Map.merge(entry, delivery_content(delivery, delivery.broadcast))
  end

  defp delivery_content(delivery, %Broadcast{} = broadcast) do
    %{
      body_markdown: broadcast.body_markdown,
      template: nil,
      reply_to_email: broadcast.reply_to_email,
      audience_name: audience_name(delivery.audience || broadcast.audience)
    }
  end

  defp delivery_content(delivery, nil) do
    metadata = delivery.metadata || %{}
    defaults = Application.get_env(:atlas, :gtm_email, [])

    %{
      body_markdown: metadata["body_markdown"],
      template: template(delivery),
      reply_to_email: metadata["reply_to_email"] || defaults[:reply_to_email],
      audience_name: audience_name(delivery.audience)
    }
  end

  defp audience_name(%Audience{name: name}), do: name
  defp audience_name(nil), do: nil

  defp template(%Delivery{kind: "transactional", metadata: metadata}), do: metadata["template"]
  defp template(%Delivery{kind: kind}) when kind in ["welcome", "confirmation"], do: kind
  defp template(_delivery), do: nil

  defp put_accounts(entries) do
    names =
      entries
      |> Enum.map(& &1.account_id)
      |> Enum.filter(&match?({:ok, _id}, Ecto.UUID.cast(&1 || "")))
      |> Enum.uniq()
      |> case do
        [] ->
          %{}

        ids ->
          Repo.all(from(account in Account, where: account.id in ^ids, select: {account.id, account.name})) |> Map.new()
      end

    Enum.map(entries, &Map.put(&1, :account_name, Map.get(names, &1.account_id)))
  end
end
