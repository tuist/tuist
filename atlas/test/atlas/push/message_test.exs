defmodule Atlas.Push.MessageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Push.Message
  alias AtlasWeb.NativeLinks

  setup do
    stub(NativeLinks.Config, :origin, fn -> "https://atlas.example.org" end)
    :ok
  end

  test "APNs groups completions by UUID and attaches only the conversation category" do
    message = %{
      registration_id: Ecto.UUID.generate(),
      notification_id: Ecto.UUID.generate(),
      screen: "orbit",
      record_id: Ecto.UUID.generate()
    }

    alert = Message.orbit_completed("Renewal review", "Ready.")
    payload = Message.apns_payload(message, alert)

    assert payload["aps"] == %{
             "alert" => %{"title" => "Renewal review", "subtitle" => "Pip", "body" => "Ready."},
             "sound" => "default",
             "category" => "ATLAS_ORBIT_COMPLETED",
             "thread-id" => message.record_id
           }

    assert payload["url"] =~ "/orbit/#{message.record_id}?server="
    another = Message.apns_payload(%{message | record_id: Ecto.UUID.generate()}, alert)
    refute another["aps"]["thread-id"] == payload["aps"]["thread-id"]

    fallback = Message.apns_payload(message, Message.orbit_completed("---", "Ready."))
    assert fallback["aps"]["alert"] == %{"title" => "Pip", "body" => "Ready."}

    assert Message.apns_payload(message)["aps"] == %{
             "alert" => %{"title" => "Atlas", "body" => "You have a new notification"},
             "sound" => "default"
           }
  end

  test "provider payloads stay within 4 KiB including emoji, routing and APNs actions" do
    message = %{
      registration_id: Ecto.UUID.generate(),
      notification_id: Ecto.UUID.generate(),
      screen: "orbit",
      record_id: Ecto.UUID.generate()
    }

    alert = Message.orbit_completed(String.duplicate("😀", 100), String.duplicate("😀", 200))
    assert byte_size(JSON.encode!(Message.apns_payload(message, alert))) < 4096
    data = Message.fcm_data(message, alert)
    assert byte_size(JSON.encode!(data)) < 4096
    assert Enum.all?(data, fn {_key, value} -> is_binary(value) end)
    assert data["title"] == alert.title and data["body"] == alert.body
    refute Map.has_key?(data, "category")
    refute Map.has_key?(data, "subtitle")
  end

  test "completion connects the conversation title with a plain reply, not a duplicated title prefix" do
    alert =
      Message.orbit_completed("## Renewal **review**", "The [proposal](https://example.org/deal_(final)) is **ready**.")

    assert alert.title == "Renewal review"
    assert alert.subtitle == "Pip"
    assert alert.body == "The proposal is ready."
    assert alert.category == "ATLAS_ORBIT_COMPLETED"
  end

  test "realistic Markdown keeps table labels, business values and reference-link labels" do
    reply = """
    ## Renewal summary
    | Account | ARR | Change |
    | :--- | ---: | ---: |
    | [Acme][account] | **€12,500** | -5% |

    > Do **not** renew `plan_v2` below €10,000; margin > 20%.

    [account]: https://example.org/accounts/acme "Acme account"
    """

    alert = Message.orbit_completed("Renewal review", reply)

    assert alert.body ==
             "Renewal summary Account: Acme; ARR: €12,500; Change: -5%. Do not renew plan_v2 below €10,000; margin > 20%."

    refute alert.body =~ ~r/[|#*`\[\]]|https:/u
  end

  test "inline punctuation and removed text do not silently change business meaning" do
    alert = Message.orbit_completed("Ticket #42", "Use `plan_v2`: ~~€15~~ €12; margin < 20%, profit > €0, C# team.")
    assert alert.title == "Ticket #42"
    assert alert.body == "Use plan_v2: (removed: €15) €12; margin < 20%, profit > €0, C# team."
  end

  test "both heading syntaxes, lists, HTML and fenced evidence become readable text" do
    reply = """
    Summary
    =======
    - **Ready** for <b>review</b>.
    - [Details](https://example.org/report).

    ```json
    {"private_tool_evidence":true}
    ```
    """

    assert Message.orbit_completed("Review", reply).body == "Summary Ready for review. Details."
  end

  test "empty or formatting-only conversation titles fall back to Pip without a duplicate subtitle" do
    for title <- ["", " \n\u202e\u0001", "---", "Pip"] do
      assert %{title: "Pip", subtitle: nil, body: "Ready."} = Message.orbit_completed(title, "Ready.")
    end
  end

  test "codepoint bounds include ellipses even for combining marks and multibyte text" do
    alert = Message.orbit_completed(String.duplicate("😀", 81), String.duplicate("e\u0301", 100))
    assert length(String.codepoints(alert.title)) == 80
    assert length(String.codepoints(alert.body)) == 160
    assert String.ends_with?(alert.title, "…")
    assert String.ends_with?(alert.body, "…")
    assert String.valid?(alert.title) and String.valid?(alert.body)
    assert byte_size(alert.title) <= 320
    assert byte_size(alert.body) <= 640

    assert Message.orbit_completed(String.duplicate("é", 80), String.duplicate("x", 160)).body ==
             String.duplicate("x", 160)
  end
end
