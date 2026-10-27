defmodule Atlas.Accounts.DealStageTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.DealStage

  test "from_key returns nil for unknown keys" do
    assert DealStage.from_key("unknown") == nil
    assert DealStage.from_key(nil) == nil
  end

  test "from_key returns the definition for known keys" do
    stage = DealStage.from_key("legal_review")

    assert stage.key == "legal_review"
    assert stage.label == "Legal Review"
    assert stage.attention == true
  end

  test "keys returns the configured stage keys" do
    assert MapSet.new(DealStage.keys()) ==
             MapSet.new([
               "closed_lost",
               "closed_won",
               "discovery",
               "legal_review",
               "negotiation",
               "poc",
               "security_review"
             ])
  end

  test "label/1 returns nil for unknown keys" do
    assert DealStage.label(nil) == nil
    assert DealStage.label("nope") == nil
  end

  test "label, color, attention, and sort order expose stage metadata" do
    assert DealStage.label(:poc) == "POC"
    assert DealStage.color("legal_review") == "warning"
    assert DealStage.color("missing") == "neutral"
    assert DealStage.attention?("security_review")
    refute DealStage.attention?("closed_won")
    assert DealStage.sort_order("closed_won") == 60
    assert DealStage.sort_order("missing") == 999
  end

  test "attention_keys covers legal and security review" do
    keys = DealStage.attention_keys()

    assert "legal_review" in keys
    assert "security_review" in keys
    refute "discovery" in keys
    refute "closed_won" in keys
  end

  test "all returns stages sorted by order" do
    stages = DealStage.all()

    assert hd(stages).key == "discovery"
    assert List.last(stages).key == "closed_lost"
  end
end
