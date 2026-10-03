defmodule Atlas.GTM.Subscriptions do
  @moduledoc """
  Confirmation, welcome, and unsubscribe flows for Atlas email subscribers.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.GTM.Audience
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.DeliverAutomatedEmail
  alias Atlas.Repo
  alias AtlasWeb.Endpoint

  @token_salt "gtm email subscription"
  @confirmation_max_age 60 * 60 * 24 * 30
  @unsubscribe_max_age 60 * 60 * 24 * 365 * 10

  def request_digest_subscription(attrs) when is_map(attrs) do
    Audit.with_context(%{interface: "api"}, fn -> do_request_digest_subscription(attrs) end)
  end

  defp do_request_digest_subscription(attrs) do
    with %Audience{} = audience <- digest_audience(),
         {:ok, subscriber} <- pending_subscriber(attrs),
         {:ok, _membership} <- ensure_pending_membership(audience, subscriber),
         {:ok, delivery} <-
           create_automated_delivery(audience, subscriber, "confirmation", "Confirm Email Digest subscription"),
         {:ok, _job} <- enqueue(delivery) do
      Audit.record("gtm_subscription.confirmation_requested", %{
        interface: "api",
        target_type: "gtm_subscriber",
        target_id: subscriber.id,
        target_label: subscriber.email,
        metadata: %{audience_id: audience.id}
      })

      {:ok, subscriber}
    else
      nil -> {:error, :digest_audience_not_found}
      error -> error
    end
  end

  def confirm(token) when is_binary(token) do
    Audit.with_context(%{interface: "api"}, fn -> do_confirm(token) end)
  end

  defp do_confirm(token) do
    with {:ok, %{"audience_id" => audience_id, "subscriber_id" => subscriber_id}} <-
           Phoenix.Token.verify(Endpoint, @token_salt, token, max_age: @confirmation_max_age),
         %Audience{} = audience <- Audiences.get_audience(audience_id),
         %Subscriber{} = subscriber <- Audiences.get_subscriber(subscriber_id),
         {:ok, subscriber} <- activate_subscription(audience, subscriber) do
      Audit.record("gtm_subscription.confirmed", %{
        interface: "api",
        target_type: "gtm_subscriber",
        target_id: subscriber.id,
        target_label: subscriber.email,
        metadata: %{audience_id: audience.id}
      })

      {:ok, %{audience: audience, subscriber: subscriber}}
    else
      {:error, _reason} -> {:error, :invalid_or_expired_token}
      nil -> {:error, :subscription_not_found}
    end
  end

  def unsubscribe(token) when is_binary(token) do
    Audit.with_context(%{interface: "api"}, fn -> do_unsubscribe(token) end)
  end

  defp do_unsubscribe(token) do
    with {:ok, %{"audience_id" => audience_id, "subscriber_id" => subscriber_id}} <-
           Phoenix.Token.verify(Endpoint, @token_salt, token, max_age: @unsubscribe_max_age),
         %Audience{} = audience <- Audiences.get_audience(audience_id),
         %Subscriber{} = subscriber <- Audiences.get_subscriber(subscriber_id),
         {:ok, _membership} <- Audiences.unsubscribe(audience, subscriber) do
      Audit.record("gtm_subscription.unsubscribed", %{
        interface: "api",
        target_type: "gtm_subscriber",
        target_id: subscriber.id,
        target_label: subscriber.email,
        metadata: %{audience_id: audience.id}
      })

      {:ok, %{audience: audience, subscriber: subscriber}}
    else
      {:error, _reason} -> {:error, :invalid_or_expired_token}
      nil -> {:error, :subscription_not_found}
    end
  end

  def maybe_enqueue_welcome(%Subscriber{} = subscriber) do
    if welcome_eligible?(subscriber) and is_nil(subscriber.welcomed_at) and subscriber.status == "subscribed" do
      audience =
        Audiences.get_audience_by_slug("users") ||
          Audiences.get_audience_by_slug("posthog-signups") ||
          digest_audience()

      with %Audience{} = audience <- audience,
           {:ok, _membership} <- Audiences.add_subscriber(audience, subscriber),
           {:ok, delivery} <- create_automated_delivery(audience, subscriber, "welcome", "Welcome to Tuist"),
           {:ok, _job} <- enqueue(delivery) do
        {:ok, delivery}
      else
        nil -> {:error, :welcome_audience_not_found}
        error -> error
      end
    else
      {:ok, :not_needed}
    end
  end

  def confirmation_url(%Delivery{} = delivery) do
    token = sign(delivery.audience_id, delivery.subscriber_id)
    Endpoint.url() <> "/email/subscriptions/confirm/#{token}"
  end

  def unsubscribe_url(%Audience{id: audience_id}, %Subscriber{id: subscriber_id}) do
    token = sign(audience_id, subscriber_id)
    Endpoint.url() <> "/email/subscriptions/unsubscribe/#{token}"
  end

  def get_delivery(id) when is_binary(id) do
    Delivery
    |> Repo.get(id)
    |> case do
      nil -> nil
      delivery -> Repo.preload(delivery, [:subscriber, :audience, broadcast: :audience])
    end
  end

  def mark_welcomed(%Subscriber{} = subscriber) do
    subscriber
    |> Ecto.Changeset.change(welcomed_at: timestamp())
    |> Repo.update()
  end

  # Re-submitting the form must not demote somebody who already confirmed.
  # `add_subscriber/4` upserts the membership status, so a blind "pending"
  # would drop a confirmed subscriber out of every broadcast until they
  # clicked a fresh link.
  defp ensure_pending_membership(audience, subscriber) do
    if Audiences.subscribed?(audience, subscriber) do
      {:ok, :already_subscribed}
    else
      Audiences.add_subscriber(audience, subscriber, nil, "pending")
    end
  end

  defp pending_subscriber(attrs) do
    email = attrs[:email] || attrs["email"]

    case is_binary(email) && Audiences.get_subscriber_by_email(email) do
      # This runs behind an unauthenticated endpoint, so a request for an
      # address that already exists only moves its status. Merging the
      # submitted attrs would let anybody who knows an email rewrite that
      # subscriber's name, user group, source, and metadata.
      %Subscriber{} = subscriber ->
        status = if subscriber.status == "subscribed", do: "subscribed", else: "pending"
        Audiences.update_subscriber(subscriber, status_map(attrs, status))

      _missing ->
        attrs
        |> Map.merge(status_map(attrs, "pending"))
        |> Audiences.create_subscriber()
    end
  end

  defp status_map(attrs, status) do
    if Enum.any?(Map.keys(attrs), &is_atom/1), do: %{status: status}, else: %{"status" => status}
  end

  defp activate_subscription(audience, subscriber) do
    Repo.transaction(fn ->
      now = timestamp()

      subscriber =
        subscriber
        |> Ecto.Changeset.change(status: "subscribed", confirmed_at: now, unsubscribed_at: nil)
        |> Repo.update!()

      # The token is valid for 30 days, long enough for the audience and its
      # memberships to have been deleted underneath it. Route the transition
      # through the audience boundary so confirmed members get the same
      # notification as members added through other interfaces.
      case Audiences.add_subscriber(audience, subscriber) do
        {:ok, _membership} -> subscriber
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_automated_delivery(audience, subscriber, kind, subject) do
    existing =
      if kind == "welcome" do
        Repo.one(
          from delivery in Delivery,
            where: delivery.subscriber_id == ^subscriber.id and delivery.kind == "welcome",
            order_by: [desc: delivery.inserted_at],
            limit: 1
        )
      end

    if existing do
      {:ok, existing}
    else
      %Delivery{audience_id: audience.id, subscriber_id: subscriber.id}
      |> Delivery.changeset(%{
        kind: kind,
        recipient_email: subscriber.email,
        recipient_name: Subscriber.display_name(subscriber),
        subject: subject
      })
      |> Repo.insert()
    end
  end

  defp enqueue(%Delivery{id: id}) do
    %{"delivery_id" => id}
    |> DeliverAutomatedEmail.new()
    |> Oban.insert()
  end

  defp welcome_eligible?(subscriber) do
    subscriber.source == "posthog" or subscriber.metadata["postHog"] == true or
      subscriber.metadata["post_hog"] == true
  end

  defp digest_audience do
    Audiences.get_audience_by_slug("email-digest") || Audiences.get_audience_by_slug("tuist-digest")
  end

  defp sign(audience_id, subscriber_id) do
    Phoenix.Token.sign(Endpoint, @token_salt, %{
      "audience_id" => audience_id,
      "subscriber_id" => subscriber_id
    })
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
