defmodule TuistOps.PagingTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.JIT.SlackClient
  alias TuistOps.Paging

  setup :verify_on_exit!

  @channel "C0BT0B97686"
  @contact "U0CAROUSELL1"

  setup do
    stub(Environment, :paging_customers, fn ->
      [
        %{
          "name" => "Carousell",
          "slackChannelId" => @channel,
          "contacts" => [%{"slackUserId" => @contact, "name" => "Jane Tan"}]
        },
        %{
          "name" => "Other",
          "slackChannelId" => "C0OTHER",
          "contacts" => [%{"slackUserId" => "U0OTHER", "name" => "Someone Else"}]
        }
      ]
    end)

    stub(Environment, :irm_api_url, fn -> "https://oncall.example.grafana.net/oncall/" end)
    stub(Environment, :irm_api_token, fn -> "irm-token" end)
    stub(Environment, :irm_team_id, fn -> "T1M1R7UYFX91B" end)

    test_pid = self()

    stub(SlackClient, :reply, fn channel, thread_ts, text ->
      send(test_pid, {:reply, channel, thread_ts, text})
      :ok
    end)

    :ok
  end

  defp mention(overrides) do
    Map.merge(
      %{
        "type" => "app_mention",
        "channel" => @channel,
        "user" => @contact,
        "ts" => "1795773300.658309",
        "text" => "<@U0TUISTOPS> builds fail for everyone since 10:00 SGT"
      },
      overrides
    )
  end

  defp expect_irm(response) do
    test_pid = self()

    expect(Req, :post, fn url, opts ->
      send(test_pid, {:irm, url, opts})
      response
    end)
  end

  test "a named contact pages the on-call team as an important escalation" do
    expect_irm({:ok, %Req.Response{status: 200, body: %{"id" => "IZHCC4GTNPZ93"}}})

    assert :ok = Paging.handle_mention(mention(%{}), false)

    assert_received {:irm, "https://oncall.example.grafana.net/oncall/api/v1/escalation/", opts}
    assert {"authorization", "irm-token"} in opts[:headers]

    assert opts[:json] == %{
             title: "Carousell: builds fail for everyone since 10:00 SGT",
             message:
               "builds fail for everyone since 10:00 SGT\n\nRaised by Jane Tan (U0CAROUSELL1) of Carousell in Slack.",
             source_url: "https://slack.com/archives/C0BT0B97686/p1795773300658309",
             team: "T1M1R7UYFX91B",
             important_team_escalation: true
           }

    assert_received {:reply, @channel, "1795773300.658309", text}
    assert text =~ "on-call engineer has been paged"
  end

  test "a mention inside a thread links to the threaded message and replies in that thread" do
    expect_irm({:ok, %Req.Response{status: 201, body: %{"id" => "I1"}}})

    Paging.handle_mention(
      mention(%{"ts" => "1795773400.000200", "thread_ts" => "1795773300.658309"}),
      false
    )

    assert_received {:irm, _url, opts}

    assert opts[:json].source_url ==
             "https://slack.com/archives/C0BT0B97686/p1795773400000200?thread_ts=1795773300.658309&cid=C0BT0B97686"

    assert_received {:reply, @channel, "1795773300.658309", _text}
  end

  test "someone who is not a named contact is told so and nobody is paged" do
    reject(&Req.post/2)

    assert :ok = Paging.handle_mention(mention(%{"user" => "U0CAROUSELL2"}), false)

    assert_received {:reply, @channel, "1795773300.658309", text}
    assert text =~ "limited to Carousell's named contacts"
    assert text =~ "Nobody was paged"
  end

  test "another customer's contact cannot page from this customer's channel" do
    reject(&Req.post/2)

    Paging.handle_mention(mention(%{"user" => "U0OTHER"}), false)

    assert_received {:reply, @channel, _ts, text}
    assert text =~ "limited to Carousell's named contacts"
  end

  test "mentions in channels without a paging customer are ignored" do
    reject(&Req.post/2)
    reject(&SlackClient.reply/3)

    assert :ok = Paging.handle_mention(mention(%{"channel" => "C0INTERNAL"}), true)
  end

  test "a mention without a message asks what's broken instead of paging" do
    reject(&Req.post/2)

    Paging.handle_mention(mention(%{"text" => "<@U0TUISTOPS>  "}), false)

    assert_received {:reply, @channel, _ts, text}
    assert text =~ "tell me what's broken"
  end

  test "a failed page retries quietly and tells the channel on the last attempt" do
    expect(Req, :post, 2, fn _url, _opts -> {:ok, %Req.Response{status: 500, body: "boom"}} end)

    assert {:error, {:http_status, 500, "boom"}} = Paging.handle_mention(mention(%{}), false)
    refute_received {:reply, _, _, _}

    assert {:error, _} = Paging.handle_mention(mention(%{}), true)
    assert_received {:reply, @channel, _ts, text}
    assert text =~ "couldn't page"
  end
end
