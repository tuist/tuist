defmodule Tuist.Webhooks.WebhookEndpointTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Webhooks.WebhookEndpoint

  defp valid_attrs(overrides \\ %{}) do
    # account_id is a foreign key with type :id; pure changeset validation
    # doesn't enforce existence, so an arbitrary integer is enough here.
    Map.merge(
      %{
        "account_id" => 1,
        "name" => "Webhook",
        "url" => "https://example.com/hook",
        "signing_secret" => "tuist_webhook_secret_value",
        "signing_secret_last_four" => "alue",
        "event_types" => ["test_case.updated"]
      },
      overrides
    )
  end

  describe "create_changeset/2" do
    test "is valid for a full set of attrs" do
      changeset = WebhookEndpoint.create_changeset(%WebhookEndpoint{}, valid_attrs())

      assert changeset.valid?
    end

    test "requires account_id, name, url, signing_secret, and signing_secret_last_four" do
      changeset = WebhookEndpoint.create_changeset(%WebhookEndpoint{}, %{})

      refute changeset.valid?

      assert errors_on(changeset)[:account_id] != []
      assert errors_on(changeset)[:name] != []
      assert errors_on(changeset)[:url] != []
      assert errors_on(changeset)[:signing_secret] != []
      assert errors_on(changeset)[:signing_secret_last_four] != []
    end

    test "rejects a blank name" do
      changeset =
        WebhookEndpoint.create_changeset(%WebhookEndpoint{}, valid_attrs(%{"name" => ""}))

      refute changeset.valid?
      assert errors_on(changeset)[:name] != []
    end

    test "rejects a name longer than 100 characters" do
      changeset =
        WebhookEndpoint.create_changeset(
          %WebhookEndpoint{},
          valid_attrs(%{"name" => String.duplicate("a", 101)})
        )

      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).name
    end

    test "rejects non-HTTPS URLs" do
      for url <- ["http://example.com/hook", "ftp://example.com/hook", "not a url"] do
        changeset =
          WebhookEndpoint.create_changeset(%WebhookEndpoint{}, valid_attrs(%{"url" => url}))

        refute changeset.valid?
        assert "must be a valid HTTPS URL" in errors_on(changeset).url
      end
    end

    test "rejects an empty event_types list" do
      changeset =
        WebhookEndpoint.create_changeset(%WebhookEndpoint{}, valid_attrs(%{"event_types" => []}))

      refute changeset.valid?
      assert "must subscribe to at least one event" in errors_on(changeset).event_types
    end

    test "rejects unsupported event types" do
      changeset =
        WebhookEndpoint.create_changeset(
          %WebhookEndpoint{},
          valid_attrs(%{"event_types" => ["test_case.updated", "nope.exploded"]})
        )

      refute changeset.valid?
      assert "contains an unsupported event type" in errors_on(changeset).event_types
    end

    test "accepts every type listed in supported_event_types/0" do
      changeset =
        WebhookEndpoint.create_changeset(
          %WebhookEndpoint{},
          valid_attrs(%{"event_types" => WebhookEndpoint.supported_event_types()})
        )

      assert changeset.valid?
    end
  end

  describe "update_changeset/2" do
    setup do
      # Build a "persisted-like" struct so update_changeset has a base
      # to merge against; signing_secret stays untouched on updates.
      endpoint = %WebhookEndpoint{
        id: UUIDv7.generate(),
        account_id: 1,
        name: "Original",
        url: "https://example.com/original",
        signing_secret: "tuist_webhook_original",
        signing_secret_last_four: "inal",
        event_types: ["test_case.updated"]
      }

      %{endpoint: endpoint}
    end

    test "updates name, url, and event_types when all three are valid", %{endpoint: endpoint} do
      changeset =
        WebhookEndpoint.update_changeset(endpoint, %{
          "name" => "Updated",
          "url" => "https://example.com/updated",
          "event_types" => ["preview.created"]
        })

      assert changeset.valid?
      assert get_change(changeset, :name) == "Updated"
      assert get_change(changeset, :url) == "https://example.com/updated"
      assert get_change(changeset, :event_types) == ["preview.created"]
    end

    test "leaves signing_secret untouched — it can only be rotated explicitly", %{
      endpoint: endpoint
    } do
      changeset =
        WebhookEndpoint.update_changeset(endpoint, %{
          "name" => "Updated",
          "signing_secret" => "tuist_webhook_attacker_supplied"
        })

      assert changeset.valid?
      refute get_change(changeset, :signing_secret)
    end

    test "rejects a blank name", %{endpoint: endpoint} do
      changeset = WebhookEndpoint.update_changeset(endpoint, %{"name" => ""})

      refute changeset.valid?
      assert errors_on(changeset)[:name] != []
    end

    test "rejects a non-HTTPS URL", %{endpoint: endpoint} do
      changeset = WebhookEndpoint.update_changeset(endpoint, %{"url" => "http://example.com/x"})

      refute changeset.valid?
      assert "must be a valid HTTPS URL" in errors_on(changeset).url
    end

    test "rejects an empty event_types list", %{endpoint: endpoint} do
      changeset = WebhookEndpoint.update_changeset(endpoint, %{"event_types" => []})

      refute changeset.valid?
      assert "must subscribe to at least one event" in errors_on(changeset).event_types
    end

    test "rejects unsupported event types", %{endpoint: endpoint} do
      changeset =
        WebhookEndpoint.update_changeset(endpoint, %{"event_types" => ["nope.exploded"]})

      refute changeset.valid?
      assert "contains an unsupported event type" in errors_on(changeset).event_types
    end
  end
end
