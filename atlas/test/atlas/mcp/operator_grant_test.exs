defmodule Atlas.MCP.OperatorGrantTest do
  use Atlas.DataCase, async: true

  import Ecto.Query

  alias Atlas.Audit.Activity
  alias Atlas.MCP
  alias Atlas.MCP.GrantRequest
  alias Atlas.MCP.OperatorGrant
  alias Atlas.Repo
  alias Atlas.Users.User

  defp user_fixture do
    %User{}
    |> User.changeset(%{email: "operator-#{System.unique_integer([:positive])}@tuist.dev", name: "Operator"})
    |> Repo.insert!()
  end

  defp grant_token(claims) do
    payload = claims |> JSON.encode!() |> Base.url_encode64(padding: false)
    header = %{"alg" => "EdDSA", "typ" => "JWT"} |> JSON.encode!() |> Base.url_encode64(padding: false)
    header <> "." <> payload <> ".signature"
  end

  defp claims(handle, exp, tier \\ "read"),
    do: %{"account_handle" => handle, "exp" => exp, "sub" => "operator@tuist.dev", "tier" => tier}

  describe "describe/1" do
    test "reads the account and expiry out of a grant payload" do
      exp = System.system_time(:second) + 600

      assert {:ok, %{account_handle: "acme", expires_at: expires_at}} =
               OperatorGrant.describe(grant_token(claims("acme", exp)))

      assert DateTime.to_unix(expires_at) == exp
    end

    test "rejects a token whose payload cannot be read" do
      assert {:error, :unreadable_grant} = OperatorGrant.describe("not-a-jwt")
      assert {:error, :unreadable_grant} = OperatorGrant.describe(grant_token(%{"sub" => "operator@tuist.dev"}))
      assert {:error, :unreadable_grant} = OperatorGrant.describe(nil)
    end

    test "reads both tiers the upstream mints" do
      exp = System.system_time(:second) + 600

      assert {:ok, %{tier: :read}} = OperatorGrant.describe(grant_token(claims("acme", exp)))
      assert {:ok, %{tier: :admin}} = OperatorGrant.describe(grant_token(claims("acme", exp, "admin")))
    end

    # An unrecognised tier is refused rather than carried: reading it as anything
    # weaker than the upstream will is how a write slips through a read proxy.
    test "refuses a tier it does not recognise" do
      exp = System.system_time(:second) + 600

      assert {:error, :unreadable_grant} = OperatorGrant.describe(grant_token(claims("acme", exp, "superuser")))

      assert {:error, :unreadable_grant} =
               OperatorGrant.describe(grant_token(%{"account_handle" => "acme", "exp" => exp}))
    end
  end

  describe "put_operator_grant/3" do
    test "stores a grant and reads it back while it is active" do
      user = user_fixture()
      token = grant_token(claims("acme", System.system_time(:second) + 600))

      assert {:ok, %OperatorGrant{account_handle: "acme"}} = MCP.put_operator_grant(user, "tuist", token)
      assert %OperatorGrant{token: ^token} = MCP.active_operator_grant(user, "tuist")
    end

    # One investigation at a time: a second grant replaces the first rather than
    # leaving Atlas to guess which account a request meant.
    test "replaces the previous grant for the same server" do
      user = user_fixture()
      exp = System.system_time(:second) + 600

      {:ok, _} = MCP.put_operator_grant(user, "tuist", grant_token(claims("acme", exp)))
      {:ok, _} = MCP.put_operator_grant(user, "tuist", grant_token(claims("globex", exp)))

      assert %OperatorGrant{account_handle: "globex"} = MCP.active_operator_grant(user, "tuist")
      assert Repo.aggregate(OperatorGrant, :count) == 1
    end

    test "an expired grant is stored but not active" do
      user = user_fixture()
      token = grant_token(claims("acme", System.system_time(:second) - 60))

      assert {:ok, _} = MCP.put_operator_grant(user, "tuist", token)
      assert is_nil(MCP.active_operator_grant(user, "tuist"))
    end

    test "refuses a token it cannot read" do
      user = user_fixture()

      assert {:error, :unreadable_grant} = MCP.put_operator_grant(user, "tuist", "nonsense")
      assert is_nil(MCP.get_operator_grant(user, "tuist"))
    end

    # Ops decides which account a grant is for, so the one that comes back can
    # disagree with the one that was asked about. Refusing it after the write
    # would cost the operator the grant they already held.
    test "a grant for another account leaves the existing one untouched" do
      user = user_fixture()
      exp = System.system_time(:second) + 600
      held = grant_token(claims("acme", exp))

      {:ok, _} = MCP.put_operator_grant(user, "tuist", held, expected_account_handle: "acme")
      audits_before = Repo.aggregate(Activity, :count)

      assert {:error, {:account_mismatch, "acme"}} =
               MCP.put_operator_grant(user, "tuist", grant_token(claims("globex", exp)),
                 expected_account_handle: "acme"
               )

      assert %OperatorGrant{account_handle: "acme", token: ^held} = MCP.active_operator_grant(user, "tuist")
      assert Repo.aggregate(OperatorGrant, :count) == 1
      assert Repo.aggregate(Activity, :count) == audits_before
    end

    test "the expected account is compared without regard to case" do
      user = user_fixture()
      token = grant_token(claims("acme", System.system_time(:second) + 600))

      assert {:ok, %OperatorGrant{account_handle: "acme"}} =
               MCP.put_operator_grant(user, "tuist", token, expected_account_handle: "ACME")
    end

    # Atlas investigates production; it has no reason to hold the tier that lets
    # an operator act on a customer's behalf.
    test "refuses an admin grant and leaves the held read grant in place" do
      user = user_fixture()
      exp = System.system_time(:second) + 600
      held = grant_token(claims("acme", exp))

      {:ok, _} = MCP.put_operator_grant(user, "tuist", held)
      audits_before = Repo.aggregate(Activity, :count)

      assert {:error, {:unsupported_grant_tier, :admin}} =
               MCP.put_operator_grant(user, "tuist", grant_token(claims("acme", exp, "admin")))

      assert %OperatorGrant{token: ^held} = MCP.active_operator_grant(user, "tuist")
      assert Repo.aggregate(OperatorGrant, :count) == 1
      assert Repo.aggregate(Activity, :count) == audits_before
    end

    test "grants belong to one user" do
      one = user_fixture()
      two = user_fixture()
      token = grant_token(claims("acme", System.system_time(:second) + 600))

      {:ok, _} = MCP.put_operator_grant(one, "tuist", token)

      assert is_nil(MCP.active_operator_grant(two, "tuist"))
    end
  end

  describe "proxyable_operator_grant/2" do
    test "yields an active read grant" do
      user = user_fixture()
      token = grant_token(claims("acme", System.system_time(:second) + 600))

      {:ok, _} = MCP.put_operator_grant(user, "tuist", token)

      assert %OperatorGrant{token: ^token} = MCP.proxyable_operator_grant(user, "tuist")
    end

    test "withholds an expired grant" do
      user = user_fixture()

      {:ok, _} = MCP.put_operator_grant(user, "tuist", grant_token(claims("acme", System.system_time(:second) - 60)))

      assert is_nil(MCP.proxyable_operator_grant(user, "tuist"))
    end

    # put_operator_grant/4 refuses an admin grant, so one can only be here from
    # before that rule — the reason the tier is re-read at the point of use
    # rather than trusted to have been checked on the way in.
    test "withholds an admin grant that was stored before the tier rule" do
      user = user_fixture()
      exp = System.system_time(:second) + 600

      %OperatorGrant{user_id: user.id, server_name: "tuist"}
      |> OperatorGrant.changeset(%{
        server_name: "tuist",
        account_handle: "acme",
        token: grant_token(claims("acme", exp, "admin")),
        expires_at: DateTime.from_unix!(exp) |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

      assert %OperatorGrant{} = MCP.active_operator_grant(user, "tuist")
      assert is_nil(MCP.proxyable_operator_grant(user, "tuist"))
    end
  end

  describe "prune_expired_operator_grants/0" do
    test "removes grants past their expiry and leaves live ones" do
      user = user_fixture()
      {:ok, _} = MCP.put_operator_grant(user, "tuist", grant_token(claims("acme", System.system_time(:second) - 60)))
      {:ok, _} = MCP.put_operator_grant(user, "other", grant_token(claims("acme", System.system_time(:second) + 600)))

      assert MCP.prune_expired_operator_grants() == 1
      assert is_nil(MCP.get_operator_grant(user, "tuist"))
      assert %OperatorGrant{} = MCP.get_operator_grant(user, "other")
    end
  end

  describe "delete_operator_grant/2" do
    test "clears a stored grant" do
      user = user_fixture()
      {:ok, _} = MCP.put_operator_grant(user, "tuist", grant_token(claims("acme", System.system_time(:second) + 600)))

      assert {:ok, _} = MCP.delete_operator_grant(user, "tuist")
      assert is_nil(MCP.get_operator_grant(user, "tuist"))
    end
  end

  describe "start_operator_grant_request/3" do
    test "points at the ops reason form and carries a state the callback can consume" do
      user = user_fixture()

      assert {:ok, offer} = MCP.start_operator_grant_request(user, "tuist", "acme")

      # Nothing here can prove the route exists in ops, but pinning it makes
      # changing it deliberate. Until this assertion existed the default named a
      # path ops has never served, and the refusal offered a link answering 404.
      assert offer.url |> URI.parse() |> Map.fetch!(:path) == "/grants/new"

      params = offer.url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
      assert params["account"] == "acme"

      return_to = URI.parse(params["return_to"])
      assert return_to.path == "/mcps/tuist/operator-grant"

      state = return_to.query |> URI.decode_query() |> Map.fetch!("state")

      # A caller handed the state directly and ops sent the state in the link
      # have to be holding the same request, or a client resuming from the
      # payload would be resuming a round trip nobody started.
      assert offer.state == state
      assert offer.account_handle == "acme"

      assert {:ok, %{account_handle: "acme"}} = MCP.consume_operator_grant_request(user, "tuist", state)
    end

    # A refused tool call can be retried in a loop, and a row per attempt would
    # leave a trail of keys behind for one question.
    test "reuses a live request for the same account" do
      user = user_fixture()

      assert {:ok, first} = MCP.start_operator_grant_request(user, "tuist", "acme")
      assert {:ok, second} = MCP.start_operator_grant_request(user, "tuist", "acme")

      assert first == second
      assert Repo.aggregate(GrantRequest, :count) == 1
    end

    test "a different account gets its own request" do
      user = user_fixture()

      assert {:ok, _} = MCP.start_operator_grant_request(user, "tuist", "acme")
      assert {:ok, _} = MCP.start_operator_grant_request(user, "tuist", "globex")

      assert Repo.aggregate(GrantRequest, :count) == 2
    end
  end

  # Without this, a crafted link could hand a logged-in operator any readable
  # token and displace the grant they were relying on.
  describe "consume_operator_grant_request/3" do
    test "is single-use" do
      user = user_fixture()
      {:ok, offer} = MCP.start_operator_grant_request(user, "tuist", "acme")
      state = offer.state

      assert {:ok, _} = MCP.consume_operator_grant_request(user, "tuist", state)
      assert {:error, :unknown_request} = MCP.consume_operator_grant_request(user, "tuist", state)
    end

    test "refuses a state belonging to another user" do
      user = user_fixture()
      other = user_fixture()
      {:ok, offer} = MCP.start_operator_grant_request(user, "tuist", "acme")

      assert {:error, :unknown_request} = MCP.consume_operator_grant_request(other, "tuist", offer.state)
    end

    test "refuses a state raised for a different server" do
      user = user_fixture()
      {:ok, offer} = MCP.start_operator_grant_request(user, "tuist", "acme")

      assert {:error, :unknown_request} = MCP.consume_operator_grant_request(user, "other", offer.state)
    end

    test "refuses a state that never existed" do
      user = user_fixture()

      assert {:error, :unknown_request} = MCP.consume_operator_grant_request(user, "tuist", Ecto.UUID.generate())
      assert {:error, :unknown_request} = MCP.consume_operator_grant_request(user, "tuist", "nonsense")
    end

    test "refuses an expired request, and still consumes it" do
      user = user_fixture()
      {:ok, offer} = MCP.start_operator_grant_request(user, "tuist", "acme")
      state = offer.state

      GrantRequest
      |> Repo.get!(state)
      |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second))
      |> Repo.update!()

      assert {:error, :expired_request} = MCP.consume_operator_grant_request(user, "tuist", state)
      assert is_nil(Repo.get(GrantRequest, state))
    end
  end

  describe "auditing" do
    test "records storing, replacing and clearing a grant, never the token" do
      user = user_fixture()
      exp = System.system_time(:second) + 600
      token = grant_token(claims("acme", exp))

      {:ok, _} = MCP.put_operator_grant(user, "tuist", token)
      {:ok, _} = MCP.put_operator_grant(user, "tuist", grant_token(claims("globex", exp)))
      {:ok, _} = MCP.delete_operator_grant(user, "tuist")

      actions = Repo.all(from(e in Activity, select: e.action))

      assert "mcp.operator_grant_stored" in actions
      assert "mcp.operator_grant_replaced" in actions
      assert "mcp.operator_grant_cleared" in actions

      metadata = Repo.all(from(e in Activity, select: e.metadata))
      refute Enum.any?(metadata, &(inspect(&1) =~ token))

      # The callback that stores a grant is a controller request, so the actor
      # has to be passed rather than inherited from a LiveView context.
      for activity <- Repo.all(Activity) do
        assert activity.actor_id == user.id
        assert activity.interface == "dashboard"
      end
    end
  end
end
