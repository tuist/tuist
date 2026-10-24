defmodule Atlas.Push.Message do
  @moduledoc """
  Bounded provider payloads.

  Activity and self-test alerts use generic text. Orbit completion is an
  explicit exception: after send-time authorization it includes the thread
  title and a short plain-text preview of that run's final reply. Native push
  registrations remain opt-in; lock-screen previews follow OS settings.
  The only routing data is the native destination (validated by `AtlasWeb.NativeLinks`
  and bound to the configured origin, never a request Host) plus the
  registration ID that Android uses to drop messages addressed to a previous
  registration. Schema version 1 is the native contract.
  """

  alias AtlasWeb.NativeLinks

  @schema_version 1
  @title "Atlas"
  @body "You have a new notification"

  def title, do: @title
  def body, do: @body

  def orbit_completed(thread_title, reply) do
    title = plain_text(thread_title, 80)
    preview = plain_text(reply, 160)
    %{title: "Pip finished", body: Enum.join(Enum.reject([title, preview], &(&1 == "")), ": ")}
  end

  def apns_payload(message, alert \\ %{title: @title, body: @body})

  def apns_payload(%{registration_id: registration_id, screen: screen, record_id: record_id}, alert) do
    maybe_put(
      %{
        "aps" => %{"alert" => %{"title" => alert.title, "body" => alert.body}, "sound" => "default"},
        "schema_version" => @schema_version,
        "registration_id" => registration_id
      },
      "url",
      url(screen, record_id)
    )
  end

  @doc """
  FCM data payload. Android renders the notification itself, so every value is a
  string, and uses `notification_id` as the local notification tag to drop
  duplicate deliveries.
  """
  def fcm_data(message, alert \\ %{title: @title, body: @body})

  def fcm_data(
        %{registration_id: registration_id, notification_id: notification_id, screen: screen, record_id: record_id},
        alert
      ) do
    maybe_put(
      %{
        "schema_version" => Integer.to_string(@schema_version),
        "title" => alert.title,
        "body" => alert.body,
        "registration_id" => registration_id,
        "notification_id" => notification_id
      },
      "url",
      url(screen, record_id)
    )
  end

  defp plain_text(text, limit) do
    text
    |> String.replace(~r/```.*?(?:```|\z)|~~~.*?(?:~~~|\z)/su, " ")
    |> String.replace(~r/!?\[([^\]]*)\]\([^)]*\)/u, "\\1")
    |> String.replace(~r/<[^>]*>/u, " ")
    |> String.replace(~r/[`*_#>~]/u, "")
    |> String.replace(~r/[\s\p{Z}\p{Cc}\p{Cf}]+/u, " ")
    |> String.trim()
    |> Stream.unfold(&String.next_codepoint/1)
    |> Enum.take(limit + 1)
    |> case do
      points when length(points) > limit -> Enum.join(Enum.take(points, limit - 1)) <> "…"
      points -> Enum.join(points)
    end
  end

  defp url(screen, record_id), do: NativeLinks.native_url({screen, record_id})

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
