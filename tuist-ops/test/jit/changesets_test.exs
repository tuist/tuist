defmodule TuistOps.JIT.ChangesetsTest do
  @moduledoc """
  Validations on `Elevation` + `Request` changesets. Most of the
  semantic correctness is downstream in Approvals / Policy / the
  policy endpoint and covered there; this file just pins the
  field-level guards on the schemas themselves so a missed field
  rename or relaxed null-check is caught locally.
  """

  use TuistOps.DataCase, async: true

  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Request

  describe "Request.create_changeset/1" do
    @valid %{
      requester_email: "marek@tuist.dev",
      requester_slack_id: "U_M",
      target_group: "group:tuist-staging-write",
      intent: "fix flaky test",
      ttl_seconds: 600,
      slack_channel_id: "C_APPROVALS",
      expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
    }

    test "valid attrs → valid changeset" do
      cs = Request.create_changeset(@valid)
      assert cs.valid?
    end

    for field <-
          ~w(requester_email requester_slack_id target_group intent ttl_seconds slack_channel_id expires_at)a do
      test "missing #{field} → invalid" do
        cs = Request.create_changeset(Map.delete(@valid, unquote(field)))
        refute cs.valid?
        assert {_msg, _} = Keyword.fetch!(cs.errors, unquote(field))
      end
    end

    test "ttl_seconds must be positive" do
      cs = Request.create_changeset(%{@valid | ttl_seconds: 0})
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :ttl_seconds)
    end

    test "intent gets a max length to keep Slack card layout sane" do
      long = String.duplicate("x", 10_000)
      cs = Request.create_changeset(%{@valid | intent: long})
      # Either rejected outright or truncated — assert the
      # contract is enforced rather than the specific bound.
      refute cs.valid?
    end
  end

  describe "Elevation transitions" do
    defp build_elevation do
      %Elevation{
        requester_email: "marek@tuist.dev",
        target_group: "group:tuist-staging-write",
        expires_at: DateTime.add(DateTime.utc_now(), 600, :second),
        status: "active"
      }
    end

    test "transition_changeset/2 to reverted is valid" do
      cs =
        Elevation.transition_changeset(build_elevation(), %{
          status: "reverted",
          reverted_at: DateTime.truncate(DateTime.utc_now(), :second)
        })

      assert cs.valid?
    end

    test "transition_changeset/2 to unknown status is rejected" do
      cs = Elevation.transition_changeset(build_elevation(), %{status: "exploded"})
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :status)
    end
  end

  describe "Request transitions" do
    test "transition_changeset/2 to denied is valid" do
      base = struct(Request, %{status: "pending"})
      cs = Request.transition_changeset(base, %{status: "denied"})
      assert cs.valid?
    end

    test "transition_changeset/2 to unknown status is rejected" do
      base = struct(Request, %{status: "pending"})
      cs = Request.transition_changeset(base, %{status: "yeeted"})
      refute cs.valid?
    end
  end
end
