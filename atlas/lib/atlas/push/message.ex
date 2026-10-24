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

    %{
      title: if(title == "", do: "Pip", else: title),
      subtitle: if(!(title == "" or title == "Pip"), do: "Pip"),
      body: preview,
      category: "ATLAS_ORBIT_COMPLETED"
    }
  end

  def apns_payload(message, alert \\ %{title: @title, body: @body})

  def apns_payload(%{registration_id: registration_id, screen: screen, record_id: record_id}, alert) do
    aps = %{
      "alert" => maybe_put(%{"title" => alert.title, "body" => alert.body}, "subtitle", Map.get(alert, :subtitle)),
      "sound" => "default"
    }

    aps =
      if Map.get(alert, :category) == "ATLAS_ORBIT_COMPLETED" and screen == "orbit" do
        aps |> Map.put("category", "ATLAS_ORBIT_COMPLETED") |> Map.put("thread-id", record_id)
      else
        aps
      end

    maybe_put(
      %{
        "aps" => aps,
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
    |> MDEx.parse_document!(extension: [table: true, strikethrough: true])
    |> node_text()
    |> String.replace(~r/[\s\p{Z}\p{Cc}\p{Cf}]+/u, " ")
    |> String.trim()
    |> Stream.unfold(&String.next_codepoint/1)
    |> Enum.take(limit + 1)
    |> case do
      points when length(points) > limit -> Enum.join(Enum.take(points, limit - 1)) <> "…"
      points -> Enum.join(points)
    end
  end

  # Parse structure rather than deleting punctuation: identifiers, comparisons and
  # amounts are business content. Link labels survive without their destinations.
  defp node_text(%MDEx.CodeBlock{}), do: " "
  defp node_text(%MDEx.HtmlBlock{}), do: " "
  defp node_text(%MDEx.HtmlInline{}), do: ""
  defp node_text(%MDEx.ThematicBreak{}), do: " "
  defp node_text(%MDEx.SoftBreak{}), do: " "
  defp node_text(%MDEx.LineBreak{}), do: " "
  defp node_text(%MDEx.Strikethrough{nodes: nodes}), do: "(removed: " <> Enum.map_join(nodes, "", &node_text/1) <> ")"

  defp node_text(%MDEx.Table{nodes: [header | rows]}) do
    Enum.map_join(rows, " ", fn row ->
      header.nodes
      |> Enum.zip(row.nodes)
      |> Enum.map_join("; ", fn {label, cell} -> node_text(label) <> ": " <> node_text(cell) end)
      |> Kernel.<>(". ")
    end)
  end

  defp node_text(%{literal: literal}) when is_binary(literal), do: literal

  defp node_text(%{__struct__: module, nodes: nodes})
       when module in [MDEx.Document, MDEx.Paragraph, MDEx.Heading, MDEx.List, MDEx.ListItem, MDEx.BlockQuote] do
    Enum.map_join(nodes, "", &node_text/1) <> " "
  end

  defp node_text(%{nodes: nodes}), do: Enum.map_join(nodes, "", &node_text/1)
  defp node_text(_node), do: ""

  defp url(screen, record_id), do: NativeLinks.native_url({screen, record_id})

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
