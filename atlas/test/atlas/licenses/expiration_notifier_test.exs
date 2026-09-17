defmodule Atlas.Licenses.ExpirationNotifierTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Licenses.ExpirationNotifier
  alias Atlas.Licenses.License

  defp account, do: %Account{id: Ecto.UUID.generate(), name: "Acme"}

  defp license(expires_on) do
    %License{
      id: Ecto.UUID.generate(),
      expires_on: expires_on,
      account: account()
    }
  end

  test "posts a Block Kit alert to the configured channel" do
    parent = self()
    today = ~D[2026-09-01]

    poster = fn app_key, channel, text, blocks ->
      send(parent, {:posted, app_key, channel, text, blocks})
      {:ok, %{"channel" => channel, "ts" => "123.456"}}
    end

    assert {:ok, %{channel_id: "C123", ts: "123.456"}} =
             ExpirationNotifier.notify(
               license(Date.add(today, 7)),
               channel_id: "C123",
               poster: poster,
               today: today
             )

    assert_received {:posted, :company, "C123", text, blocks}
    assert text =~ "Acme"
    assert text =~ "7 days"
    assert text =~ "September 8, 2026"
    assert is_list(blocks)
    assert Enum.any?(blocks, &(&1["type"] == "header"))
  end

  test "renders the countdown in the body block with the account link and expiration" do
    today = ~D[2026-09-01]

    body_text =
      account()
      |> then(&%{license(Date.add(today, 7)) | account: &1})
      |> then(&ExpirationNotifier.build_blocks(&1.account, &1, today))
      |> Enum.map(&get_in(&1, ["text", "text"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    assert body_text =~ "license expires in *7 days*"
    assert body_text =~ "September 8, 2026"
  end

  test "singularizes the countdown when only one day remains" do
    today = ~D[2026-09-01]

    body_text =
      today
      |> Date.add(1)
      |> license()
      |> then(&ExpirationNotifier.build_blocks(&1.account, &1, today))
      |> Enum.map(&get_in(&1, ["text", "text"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    assert body_text =~ "license expires in *1 day*"
  end

  test "returns an error when no channel is configured" do
    poster = fn _app, _channel, _text, _blocks -> flunk("should not post without a channel") end

    assert {:error, :missing_expiration_slack_channel_id} =
             ExpirationNotifier.notify(
               license(~D[2026-09-08]),
               licenses_config: [],
               poster: poster,
               today: ~D[2026-09-01]
             )
  end
end
