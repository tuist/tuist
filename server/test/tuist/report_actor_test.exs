defmodule Tuist.ReportActorTest do
  use ExUnit.Case, async: true

  alias Tuist.Accounts.Account
  alias Tuist.ReportActor

  test "verified identity wins over a reported identifier" do
    record = %{actor_account: %Account{name: "verified"}, claimed_actor_id: "someone-else", submission_auth: "token"}
    assert %{name: "verified", source: :verified} = ReportActor.actor(record)
  end

  test "shared token publishers are not presented as verified people" do
    record = %{
      ran_by_account: %Account{name: "organization"},
      claimed_actor_id: "developer-123",
      submission_auth: "token"
    }

    assert %{name: "developer-123", source: :reported} = ReportActor.actor(record)
    assert %{name: "Unknown", source: :unknown} = ReportActor.actor(%{record | claimed_actor_id: ""})
  end

  test "legacy records preserve existing attribution" do
    assert %{name: "legacy", source: :legacy} = ReportActor.actor(%{ran_by_account: %Account{name: "legacy"}})
  end

  test "reported Bazel users are unverified, never the publisher organization" do
    record = %{custom_values: %{"tuist.reported_user" => "developer"}}
    assert %{name: "developer", source: :reported} = ReportActor.actor(record)
  end

  test "historical client metadata cannot replace a loaded historical account" do
    record = %{ran_by_account: %Account{name: "historical"}, custom_values: %{"tuist.reported_user" => "someone-else"}}
    assert %{name: "historical", source: :legacy} = ReportActor.actor(record)
    record = %{ran_by_account: %Ecto.Association.NotLoaded{}, built_by_account: %Account{name: "historical"}}
    assert %{name: "historical", source: :legacy} = ReportActor.actor(record)
  end

  test "bounds identifiers and rejects header injection and ambiguous display characters" do
    assert ReportActor.valid_identifier?("developer@example.com")
    assert ReportActor.valid_identifier?(String.duplicate("a", 128))

    for id <- [nil, "", String.duplicate("a", 129), "a\r\nb", "a\t", "a b", "é", <<255>>] do
      refute ReportActor.valid_identifier?(id)
    end
  end
end
