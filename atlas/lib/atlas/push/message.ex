defmodule Atlas.Push.Message do
  @moduledoc """
  Privacy-safe provider payloads.

  Every alert uses the same generic title and body so lock screens never reveal
  record names, customers, amounts or people. The only routing data is the
  existing native custom-scheme destination (validated by `AtlasWeb.NativeLinks`
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

  def apns_payload(%{registration_id: registration_id, screen: screen, record_id: record_id}) do
    maybe_put(
      %{
        "aps" => %{"alert" => %{"title" => @title, "body" => @body}, "sound" => "default"},
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
  def fcm_data(%{
        registration_id: registration_id,
        notification_id: notification_id,
        screen: screen,
        record_id: record_id
      }) do
    maybe_put(
      %{
        "schema_version" => Integer.to_string(@schema_version),
        "title" => @title,
        "body" => @body,
        "registration_id" => registration_id,
        "notification_id" => notification_id
      },
      "url",
      url(screen, record_id)
    )
  end

  defp url(screen, record_id), do: NativeLinks.native_url({screen, record_id})

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
