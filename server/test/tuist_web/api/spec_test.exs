defmodule TuistWeb.API.SpecTest do
  use ExUnit.Case, async: true

  alias Tuist.Webhooks.WebhookEndpoint
  alias TuistWeb.API.Spec

  describe "webhook event schemas" do
    test "components.schemas contains a schema for every supported event type" do
      schema_titles =
        Spec.spec().components.schemas
        |> Map.keys()
        |> MapSet.new()

      expected_titles =
        WebhookEndpoint.event_groups()
        |> Enum.flat_map(& &1.events)
        |> Enum.map(&event_schema_title(&1.type))

      for title <- expected_titles do
        assert title in schema_titles,
               "missing webhook event schema #{inspect(title)} — every event in " <>
                 "WebhookEndpoint.event_groups/0 must have a matching " <>
                 "OpenApiSpex schema in components.schemas"
      end
    end

    test "the Webhook events tag description lists every supported event type" do
      tag =
        Spec.spec().tags
        |> Enum.find(&(&1.name == Spec.webhook_events_tag()))

      assert tag, "expected a `#{Spec.webhook_events_tag()}` tag on the spec"

      for %{events: events} <- WebhookEndpoint.event_groups(),
          %{type: type} <- events do
        assert tag.description =~ "`#{type}`",
               "webhook event #{inspect(type)} is missing from the " <>
                 "`#{Spec.webhook_events_tag()}` tag description — the docs portal won't list it"
      end
    end
  end

  # Mirror the naming convention used by the schema modules
  # (Webhook<CamelEventType>Event), translated from the dotted event
  # type strings the dispatcher emits.
  defp event_schema_title(type) do
    suffix =
      type
      |> String.split(".")
      |> Enum.map_join("", fn part ->
        part |> String.split("_") |> Enum.map_join("", &String.capitalize/1)
      end)

    "Webhook" <> suffix <> "Event"
  end
end
