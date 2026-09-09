defmodule Tuist.Kura.PlacementNotifierTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.PlacementNotifier
  alias Tuist.Kura.PlacementProposal
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  # Delivery runs in a detached task, so the stub has to hold outside the test
  # process for the message to be readable at all.
  setup :set_mimic_global

  setup do
    stub(Environment, :ops_slack_webhook_url, fn -> "https://hooks.slack.test/webhook" end)
    stub(Environment, :env, fn -> :production end)

    test_process = self()

    stub(Req, :post, fn _url, options ->
      send(test_process, {:posted, options[:json].text})
      {:ok, %Req.Response{status: 200}}
    end)

    :ok
  end

  test "says which region a relocation gives up" do
    proposal =
      proposal(%{
        kind: :relocate,
        from_region: "us-west",
        to_region: "us-east",
        evidence: %{"retire_source" => true, "region_runs" => 44_928, "share" => 0.984, "active_days" => 10}
      })

    assert :ok = PlacementNotifier.notify_applied(proposal)

    assert_receive {:posted, text}
    assert text =~ "relocate us-west -> us-east"
    assert text =~ "retiring us-west"
    assert text =~ "(44928 runs, 98% of traffic, 10 active days)"
  end

  test "says when a relocation keeps the region it moved off" do
    # The difference between a move that costs a region's cache refill and one
    # that only changes which region is primary.
    proposal =
      proposal(%{
        kind: :relocate,
        from_region: "us-west",
        to_region: "us-east",
        evidence: %{"retire_source" => false}
      })

    assert :ok = PlacementNotifier.notify_applied(proposal)

    assert_receive {:posted, text}
    assert text =~ "keeping us-west"
    refute text =~ "retiring"
  end

  test "gives up nothing for an expansion" do
    proposal = proposal(%{kind: :expand, from_region: nil, to_region: "sa-west", evidence: %{"region_runs" => 1071}})

    assert :ok = PlacementNotifier.notify_applied(proposal)

    assert_receive {:posted, text}
    assert text =~ "expand -> sa-west"
    refute text =~ "retiring"
    refute text =~ "keeping"
  end

  test "stays quiet without a webhook" do
    stub(Environment, :ops_slack_webhook_url, fn -> nil end)

    assert :ok = PlacementNotifier.notify_applied(proposal(%{kind: :expand, to_region: "sa-west"}))

    refute_receive {:posted, _text}
  end

  defp proposal(attrs) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    %PlacementProposal{}
    |> PlacementProposal.changeset(Map.merge(%{account_id: account.id, evidence: %{}}, attrs))
    |> Repo.insert!()
  end
end
