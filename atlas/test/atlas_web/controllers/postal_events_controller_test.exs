defmodule AtlasWeb.PostalEventsControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Audit.Activity
  alias Atlas.Letters.Letter
  alias Atlas.Repo
  alias Atlas.Users.User
  alias AtlasWeb.PostalEventsController

  test "accepts a signed delivery confirmation and persists it", %{conn: conn} do
    letter = insert_sent_letter!()

    payload = %{
      "data" => %{
        "id" => "event-#{System.unique_integer([:positive])}",
        "type" => "webhook_delivered",
        "attributes" => %{"created_at" => "2026-08-28T09:30:00Z"},
        "relationships" => %{"letter" => %{"data" => %{"id" => letter.pingen_letter_id}}}
      }
    }

    raw_body = JSON.encode!(payload)

    conn =
      conn
      |> put_req_header("signature", signature(raw_body))
      |> put_private(:raw_body, raw_body)
      |> put_private(:postal_webhook_signing_key, "postal-signing-key")
      |> PostalEventsController.handle(payload)

    assert conn.status == 200
    assert JSON.decode!(conn.resp_body) == %{"ok" => true}

    delivered = Repo.get!(Letter, letter.id)
    assert delivered.status == "delivered"
    assert delivered.delivered_at

    activity = Repo.get_by!(Activity, action: "letter.webhook_received", target_id: letter.id)
    assert activity.interface == "api"
  end

  test "rejects an unsigned delivery event", %{conn: conn} do
    raw_body = "{\"data\":{}}"

    conn =
      conn
      |> put_req_header("signature", "not-valid")
      |> put_private(:raw_body, raw_body)
      |> put_private(:postal_webhook_signing_key, "postal-signing-key")
      |> PostalEventsController.handle(%{"data" => %{}})

    assert conn.status == 401
    assert JSON.decode!(conn.resp_body) == %{"error" => "invalid signature"}
  end

  defp signature(raw_body) do
    :crypto.mac(:hmac, :sha256, "postal-signing-key", raw_body)
    |> Base.encode16(case: :lower)
  end

  defp insert_sent_letter! do
    suffix = System.unique_integer([:positive])

    user =
      %User{}
      |> User.changeset(%{
        email: "postal-event-user-#{suffix}@tuist.dev",
        name: "Postal Event User",
        role: :executive
      })
      |> Repo.insert!()

    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "postal-event-account-#{suffix}",
        name: "Postal Event Account",
        segment: :customer
      })
      |> Repo.insert!()

    %Letter{
      id: Atlas.UUIDv7.generate(),
      account_id: account.id,
      created_by_id: user.id,
      confirmed_by_id: user.id,
      kind: "tax_certificate_request",
      status: "sent",
      recipient_name: "Finanzamt Berlin",
      recipient_street: "Musterstraße 1",
      recipient_postal_code: "10115",
      recipient_city: "Berlin",
      recipient_country: "DE",
      sender_name: "Atlas GmbH",
      sender_street: "Musterstraße 42",
      sender_postal_code: "10115",
      sender_city: "Berlin",
      sender_country: "DE",
      signatory_name: "Mia Example",
      tax_id: "30/123/45678",
      subject: "Tax certificate request",
      body: "Please issue a tax certificate.",
      pingen_letter_id: "provider-letter-#{suffix}",
      pingen_events: %{"items" => []},
      confirmed_at: ~U[2026-08-26 12:00:00Z],
      sent_at: ~U[2026-08-26 12:00:00Z]
    }
    |> Repo.insert!()
  end
end
