defmodule Atlas.GTM.ContactIngest do
  @moduledoc """
  Loops-compatible contact ingestion for the PostHog signup pipeline.

  PostHog pushes product signups into an email tool through a data pipeline
  destination: on `$identify` and `$set` events it sends the person to
  `PUT https://app.loops.so/api/v1/contacts/update` with a Bearer API key. Loops
  upserts the contact and its own workflow sends the welcome email.

  Atlas replaces Loops, so it accepts the same payload shape and the PostHog
  destination only changes URL and key. Fields follow Loops' contact API:
  `email`, `userId`, `firstName`, `lastName`, `userGroup`, `source`,
  `subscribed`, and `mailingLists` (a map of list id to subscription boolean).
  Anything else is a custom property and is kept in the subscriber metadata.

  Mailing list ids resolve against `Audience.source_id`, which is where the
  Loops list id belongs, and fall back to the audience slug.

  The welcome email is not sent from here. `Atlas.GTM.Audiences.create_subscriber/3`
  runs `Atlas.GTM.Subscriptions.maybe_enqueue_welcome/1` for newly created
  subscribers, which is the Atlas equivalent of the Loops workflow.
  """

  alias Atlas.Audit
  alias Atlas.GTM.Audiences

  # Loops' own contact fields. Everything else in the payload is a custom
  # property and travels into the subscriber metadata.
  @profile_keys ~w(email userId firstName lastName userGroup source subscribed mailingLists)
  @default_source "posthog"

  def upsert_contact(payload) when is_map(payload) do
    Audit.with_context(%{interface: "api"}, fn -> do_upsert_contact(payload) end)
  end

  defp do_upsert_contact(payload) do
    with {:ok, email} <- fetch_email(payload) do
      existing = Audiences.get_subscriber_by_email(email)

      case Audiences.upsert_subscriber(subscriber_attrs(email, payload, existing)) do
        {:ok, subscriber} ->
          {applied, ignored} = apply_mailing_lists(subscriber, payload)

          Audit.record("gtm_subscriber.contact_ingested", %{
            interface: "api",
            target_type: "gtm_subscriber",
            target_id: subscriber.id,
            target_label: subscriber.email,
            metadata: %{
              created: is_nil(existing),
              source: subscriber.source,
              mailing_lists: applied,
              unknown_mailing_lists: ignored
            }
          })

          {:ok,
           %{
             subscriber: subscriber,
             created: is_nil(existing),
             mailing_lists: applied,
             unknown_mailing_lists: ignored
           }}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp fetch_email(payload) do
    case present_string(payload["email"]) do
      nil -> {:error, :email_missing}
      email -> {:ok, email}
    end
  end

  defp subscriber_attrs(email, payload, existing) do
    %{
      "email" => email,
      "first_name" => present_string(payload["firstName"]),
      "last_name" => present_string(payload["lastName"]),
      "user_group" => present_string(payload["userGroup"]),
      "source" => present_string(payload["source"]) || @default_source,
      "metadata" => metadata(payload, existing)
    }
    |> reject_nil_values()
    |> put_status(payload, existing)
  end

  # An identify event carries no subscription intent, so an absent `subscribed`
  # leaves the current status alone. Re-identifying somebody who unsubscribed
  # must not resubscribe them.
  defp put_status(attrs, payload, existing) do
    case {payload["subscribed"], existing} do
      {nil, nil} -> Map.put(attrs, "status", "subscribed")
      {nil, _existing} -> attrs
      {value, _existing} when value in [false, "false"] -> Map.put(attrs, "status", "unsubscribed")
      {_truthy, _existing} -> Map.put(attrs, "status", "subscribed")
    end
  end

  defp metadata(payload, existing) do
    custom =
      payload
      |> Enum.reject(fn {key, value} -> key in @profile_keys or is_nil(value) end)
      |> Map.new()

    existing_metadata = if existing, do: existing.metadata || %{}, else: %{}

    existing_metadata
    |> Map.merge(custom)
    |> put_present("userId", present_string(payload["userId"]))
  end

  defp apply_mailing_lists(subscriber, payload) do
    payload
    |> Map.get("mailingLists")
    |> case do
      lists when is_map(lists) -> lists
      _other -> %{}
    end
    |> Enum.reduce({[], []}, fn {list_id, subscribed}, {applied, ignored} ->
      with audience when not is_nil(audience) <- find_audience(list_id),
           :ok <- apply_membership(audience, subscriber, subscribed) do
        {[list_id | applied], ignored}
      else
        _unresolved_or_failed -> {applied, [list_id | ignored]}
      end
    end)
    |> then(fn {applied, ignored} -> {Enum.reverse(applied), Enum.reverse(ignored)} end)
  end

  defp apply_membership(audience, subscriber, subscribed) do
    if subscribed in [false, "false"] do
      case Audiences.unsubscribe(audience, subscriber) do
        {:ok, _membership} -> :ok
        # Never a member, so the requested end state already holds.
        {:error, :membership_not_found} -> :ok
        {:error, _reason} = error -> error
      end
    else
      case Audiences.add_subscriber(audience, subscriber) do
        {:ok, _membership} -> :ok
        {:error, _reason} = error -> error
      end
    end
  end

  defp find_audience(list_id) when is_binary(list_id) do
    Audiences.get_audience_by_source_id(list_id) || Audiences.get_audience_by_slug(list_id)
  end

  defp find_audience(_list_id), do: nil

  defp reject_nil_values(attrs) do
    attrs |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil
end
