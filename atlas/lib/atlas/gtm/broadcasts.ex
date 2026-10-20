defmodule Atlas.GTM.Broadcasts do
  @moduledoc """
  Builds immutable recipient snapshots and queues audience broadcasts.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Broadcast
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.DeliverBroadcast
  alias Atlas.Repo
  alias Ecto.Multi

  @max_delivery_attempts 5

  def get_broadcast(id) when is_binary(id) do
    Broadcast
    |> Repo.get(id)
    |> case do
      nil -> nil
      broadcast -> Repo.preload(broadcast, [:audience, :sender, :deliveries])
    end
  end

  @doc """
  Broadcast history for an audience, newest first, paginated.
  """
  def list_broadcasts(%Audience{id: audience_id}, opts \\ []) do
    from(broadcast in Broadcast,
      where: broadcast.audience_id == ^audience_id,
      preload: [:sender]
    )
    |> Audiences.paginate_association([desc: dynamic([b], b.inserted_at)], opts)
  end

  def change_broadcast(%Audience{} = audience, attrs \\ %{}, sender \\ nil) do
    defaults = email_defaults()

    %Broadcast{audience_id: audience.id, sender_id: sender && sender.id}
    |> Broadcast.changeset(
      Map.merge(
        %{
          "from_name" => defaults[:from_name],
          "from_email" => defaults[:from_email],
          "reply_to_email" => defaults[:reply_to_email]
        },
        stringify_keys(attrs)
      )
    )
  end

  def queue_broadcast(%Audience{} = audience, attrs, sender \\ nil) when is_map(attrs) do
    recipients = Audiences.subscribed_recipients(audience)
    changeset = change_broadcast(audience, attrs, sender)

    if recipients == [] do
      {:error, Ecto.Changeset.add_error(changeset, :audience_id, "has no subscribed recipients")}
    else
      Multi.new()
      |> Multi.insert(:broadcast, changeset)
      |> Multi.run(:deliveries, fn repo, %{broadcast: broadcast} ->
        insert_deliveries(repo, broadcast, audience, recipients)
      end)
      |> Multi.run(:job, fn repo, %{broadcast: broadcast} ->
        %{"broadcast_id" => broadcast.id}
        |> DeliverBroadcast.new()
        |> Oban.insert(repo: repo)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{broadcast: broadcast}} ->
          broadcast = get_broadcast(broadcast.id)

          Audit.record(
            "gtm_broadcast.queued",
            %{
              target_type: "gtm_broadcast",
              target_id: broadcast.id,
              target_label: broadcast.subject,
              metadata: %{audience_id: audience.id, recipients_count: broadcast.recipients_count}
            },
            actor: sender
          )

          {:ok, broadcast}

        {:error, :broadcast, failed_changeset, _changes} ->
          {:error, failed_changeset}

        {:error, _operation, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  How many times a single recipient is attempted before it is given up on.

  Bounds the resume worker so a permanently undeliverable address cannot be
  retried forever.
  """
  def max_delivery_attempts, do: @max_delivery_attempts

  def list_pending_deliveries(%Broadcast{id: broadcast_id}) do
    from(delivery in Delivery,
      where: delivery.broadcast_id == ^broadcast_id,
      where: delivery.status in ["pending", "failed"],
      where: delivery.attempts < @max_delivery_attempts,
      order_by: [asc: delivery.inserted_at],
      preload: [:subscriber, :audience]
    )
    |> Repo.all()
  end

  @doc """
  Broadcasts whose delivery run stopped part way through and still has work
  left, such as when the queue drained during a provider outage or the job was
  discarded after exhausting its attempts.

  Only broadcasts untouched since `stale_before` are returned so a run that is
  still in progress is left alone.
  """
  def list_resumable_broadcasts(%DateTime{} = stale_before) do
    resumable_deliveries =
      from(delivery in Delivery,
        where: delivery.broadcast_id == parent_as(:broadcast).id,
        where: delivery.status in ["pending", "failed"],
        where: delivery.attempts < @max_delivery_attempts,
        select: 1
      )

    from(broadcast in Broadcast,
      as: :broadcast,
      where: broadcast.status in ["pending", "sending", "failed"],
      where: broadcast.updated_at < ^stale_before,
      where: exists(resumable_deliveries),
      order_by: [asc: broadcast.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Welcome and confirmation deliveries that never reached a terminal state, for
  the same reasons a broadcast stalls. These carry no broadcast, so they are
  resumed one job per delivery.
  """
  def list_resumable_automated_deliveries(%DateTime{} = stale_before) do
    from(delivery in Delivery,
      where: is_nil(delivery.broadcast_id),
      where: delivery.status in ["pending", "failed"],
      where: delivery.attempts < @max_delivery_attempts,
      where: delivery.updated_at < ^stale_before,
      order_by: [asc: delivery.inserted_at]
    )
    |> Repo.all()
  end

  def mark_sending(%Broadcast{} = broadcast) do
    broadcast
    |> Ecto.Changeset.change(status: "sending")
    |> Repo.update()
  end

  def finalize(%Broadcast{} = broadcast) do
    counts =
      from(delivery in Delivery,
        where: delivery.broadcast_id == ^broadcast.id,
        group_by: delivery.status,
        select: {delivery.status, count(delivery.id)}
      )
      |> Repo.all()
      |> Map.new()

    failed_count = Map.get(counts, "failed", 0)
    pending_count = Map.get(counts, "pending", 0)
    status = if failed_count == 0 and pending_count == 0, do: "sent", else: "failed"
    now = timestamp()

    result =
      broadcast
      |> Ecto.Changeset.change(%{
        status: status,
        delivered_count: Map.get(counts, "delivered", 0),
        failed_count: failed_count,
        skipped_count: Map.get(counts, "skipped", 0),
        sent_at: if(status == "sent", do: now)
      })
      |> Repo.update()

    tap(result, fn
      {:ok, updated} ->
        Audit.record("gtm_broadcast.#{updated.status}", %{
          interface: "worker",
          target_type: "gtm_broadcast",
          target_id: updated.id,
          target_label: updated.subject,
          metadata: %{
            audience_id: updated.audience_id,
            delivered_count: updated.delivered_count,
            failed_count: updated.failed_count,
            skipped_count: updated.skipped_count
          }
        })

      _result ->
        :ok
    end)
  end

  def update_delivery(%Delivery{} = delivery, attrs) do
    result =
      delivery
      |> Delivery.changeset(count_attempt(delivery, attrs))
      |> Repo.update()

    tap(result, fn
      {:ok, updated} when updated.status in ["delivered", "failed", "skipped"] ->
        Audit.record("gtm_delivery.#{updated.status}", %{
          interface: "worker",
          target_type: "gtm_delivery",
          target_id: updated.id,
          target_label: updated.recipient_email,
          metadata: %{
            audience_id: updated.audience_id,
            broadcast_id: updated.broadcast_id,
            kind: updated.kind,
            provider_message_id: updated.provider_message_id,
            error: updated.error
          }
        })

      _result ->
        :ok
    end)
  end

  # Every failed send counts, so a permanently undeliverable address stops being
  # resumed instead of being retried forever.
  defp count_attempt(%Delivery{} = delivery, %{status: "failed"} = attrs) do
    Map.put(attrs, :attempts, (delivery.attempts || 0) + 1)
  end

  defp count_attempt(_delivery, attrs), do: attrs

  defp insert_deliveries(repo, broadcast, audience, recipients) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(recipients, fn subscriber ->
        %{
          id: Atlas.UUIDv7.generate(),
          broadcast_id: broadcast.id,
          audience_id: audience.id,
          subscriber_id: subscriber.id,
          kind: "broadcast",
          recipient_email: subscriber.email,
          recipient_name: Subscriber.display_name(subscriber),
          subject: broadcast.subject,
          status: "pending",
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, rows} = repo.insert_all(Delivery, entries, returning: true)

    broadcast
    |> Ecto.Changeset.change(recipients_count: length(entries))
    |> repo.update()
    |> case do
      {:ok, _broadcast} -> {:ok, rows}
      {:error, reason} -> {:error, reason}
    end
  end

  defp email_defaults do
    Application.get_env(:atlas, :gtm_email, [])
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
