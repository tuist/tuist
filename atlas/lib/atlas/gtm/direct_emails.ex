defmodule Atlas.GTM.DirectEmails do
  @moduledoc """
  Per-recipient transactional email.

  A broadcast targets an audience: it appends an unsubscribe footer, sets
  `List-Unsubscribe` headers, and skips anybody who is no longer subscribed.
  None of that is correct for a notice the recipient is entitled to receive,
  such as a price change or a contract term. Somebody who left the marketing
  digest months ago must still be told their price is changing, and must not
  be invited to opt out of being told.

  So a direct send addresses one recipient, optionally with other addresses in
  CC on the same message, carries no unsubscribe affordance, and never reads subscriber status or audience membership. It still writes a
  `Delivery` row before sending, which gives it the same audit trail, provider
  idempotency key, retry, and stalled-delivery recovery as every other Atlas
  email.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Workers.DeliverDirectEmail
  alias Atlas.Repo

  @kind "direct"

  @email_format ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  # An agent that times out and calls again must not send a second copy. A
  # repeat of the same recipient, CC addresses, subject, and body inside this
  # window returns the delivery that is already queued.
  @dedupe_window_seconds 15 * 60

  # A UUID collision is exceptionally unlikely but recoverable. Keep the retry
  # bounded so a faulty generator still returns a useful error to callers.
  @primary_key_insert_attempts 3

  def kind, do: @kind

  @doc """
  Queues a direct email to one recipient, copying any `cc_emails` on the same
  message. CC addresses are validated, deduplicated, and dropped when they
  match the recipient.

  Returns `{:ok, %{delivery: delivery, duplicate: boolean}}`, or an error of
  `{:error, {:invalid, field, message}}` for a rejected argument and
  `{:error, %Ecto.Changeset{}}` / `{:error, reason}` for a failed write.
  """
  def queue(attrs, sender \\ nil) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, recipient_email} <- fetch_email(attrs, "recipient_email"),
         {:ok, cc_emails} <- fetch_cc_emails(attrs, recipient_email),
         {:ok, subject} <- fetch_required(attrs, "subject"),
         {:ok, body_markdown} <- fetch_required(attrs, "body_markdown"),
         {:ok, from_email} <- fetch_optional_email(attrs, "from_email"),
         {:ok, reply_to_email} <- fetch_optional_email(attrs, "reply_to_email") do
      metadata =
        drop_blanks(%{
          "body_markdown" => body_markdown,
          "from_name" => trimmed(attrs["from_name"]),
          "from_email" => from_email,
          "reply_to_email" => reply_to_email,
          "account_id" => account_field(attrs["account"], :id),
          "account_key" => account_field(attrs["account"], :account_key)
        })

      send_or_return_duplicate(
        %{
          kind: @kind,
          recipient_email: recipient_email,
          recipient_name: trimmed(attrs["recipient_name"]),
          cc_emails: cc_emails,
          subject: subject,
          status: "pending",
          metadata: metadata
        },
        sender
      )
    end
  end

  @doc """
  Loads a direct delivery. Returns `nil` for an id that is missing or belongs
  to another kind of delivery, so the worker cannot act on a broadcast row.
  """
  def get_delivery(id) when is_binary(id) do
    Repo.get_by(Delivery, id: id, kind: @kind)
  end

  defp send_or_return_duplicate(attrs, sender) do
    case recent_duplicate(attrs) do
      %Delivery{} = delivery ->
        {:ok, %{delivery: delivery, duplicate: true}}

      nil ->
        with {:ok, delivery} <- insert_delivery(attrs, @primary_key_insert_attempts),
             {:ok, _job} <- enqueue(delivery) do
          Audit.record(
            "gtm_direct_email.queued",
            %{
              target_type: "gtm_delivery",
              target_id: delivery.id,
              target_label: delivery.recipient_email,
              metadata: %{
                subject: delivery.subject,
                cc_emails: delivery.cc_emails,
                account_id: delivery.metadata["account_id"],
                account_key: delivery.metadata["account_key"]
              }
            },
            actor: sender
          )

          {:ok, %{delivery: delivery, duplicate: false}}
        end
    end
  end

  defp insert_delivery(attrs, attempts_remaining) do
    %Delivery{}
    |> Delivery.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:error, changeset} when attempts_remaining > 1 ->
        if primary_key_collision?(changeset) do
          insert_delivery(attrs, attempts_remaining - 1)
        else
          {:error, changeset}
        end

      result ->
        result
    end
  end

  defp primary_key_collision?(changeset) do
    Enum.any?(changeset.errors, fn
      {:id, {_message, options}} ->
        options[:constraint] == :unique && options[:constraint_name] == "gtm_deliveries_pkey"

      _other ->
        false
    end)
  end

  # Every candidate in the window is considered, not just the most recent one.
  # Limiting to the latest would miss the duplicate as soon as another direct
  # email to the same address landed in between.
  defp recent_duplicate(attrs) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@dedupe_window_seconds, :second)
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()

    from(delivery in Delivery,
      where: delivery.kind == @kind,
      where: delivery.recipient_email == ^attrs.recipient_email,
      where: delivery.subject == ^attrs.subject,
      where: delivery.status in ["pending", "delivered"],
      where: delivery.inserted_at >= ^since,
      order_by: [desc: delivery.inserted_at]
    )
    |> Repo.all()
    |> Enum.find(
      &(&1.metadata["body_markdown"] == attrs.metadata["body_markdown"] and
          cc_key(&1.cc_emails) == cc_key(attrs.cc_emails))
    )
  end

  # The same CC addresses in another order or capitalization are the same email.
  defp cc_key(addresses), do: addresses |> Enum.map(&String.downcase/1) |> Enum.sort()

  defp enqueue(%Delivery{id: id}) do
    %{"delivery_id" => id}
    |> DeliverDirectEmail.new()
    |> Oban.insert()
  end

  defp fetch_required(attrs, field) do
    case trimmed(attrs[field]) do
      nil -> {:error, {:invalid, field, "is required"}}
      value -> {:ok, value}
    end
  end

  defp fetch_email(attrs, field) do
    with {:ok, value} <- fetch_required(attrs, field) do
      validate_email(field, value)
    end
  end

  defp fetch_optional_email(attrs, field) do
    case trimmed(attrs[field]) do
      nil -> {:ok, nil}
      value -> validate_email(field, value)
    end
  end

  defp fetch_cc_emails(attrs, recipient_email) do
    case attrs["cc_emails"] do
      nil ->
        {:ok, []}

      addresses when is_list(addresses) ->
        with {:ok, addresses} <- validate_cc_emails(addresses) do
          {:ok,
           addresses
           |> Enum.reject(&same_address?(&1, recipient_email))
           |> Enum.uniq_by(&String.downcase/1)}
        end

      _addresses ->
        {:error, {:invalid, "cc_emails", "must be a list of email addresses"}}
    end
  end

  defp validate_cc_emails(addresses) do
    results = Enum.map(addresses, &cc_email/1)

    case Enum.find(results, &match?({:error, _reason}, &1)) do
      nil -> {:ok, for({:ok, address} <- results, address, do: address)}
      error -> error
    end
  end

  defp cc_email(address) when is_binary(address) do
    case trimmed(address) do
      nil ->
        {:ok, nil}

      value ->
        if Regex.match?(@email_format, value) do
          {:ok, value}
        else
          {:error, {:invalid, "cc_emails", "contains an invalid email address: #{value}"}}
        end
    end
  end

  defp cc_email(_address), do: {:error, {:invalid, "cc_emails", "must be a list of email addresses"}}

  defp same_address?(left, right), do: String.downcase(left) == String.downcase(right)

  defp validate_email(field, value) do
    if Regex.match?(@email_format, value) do
      {:ok, value}
    else
      {:error, {:invalid, field, "is not a valid email address"}}
    end
  end

  defp account_field(%Account{} = account, field), do: Map.get(account, field)
  defp account_field(_account, _field), do: nil

  defp drop_blanks(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed(_value), do: nil

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
