defmodule Atlas.Accounts.POCsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.FeatureInterest
  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.AccessRequest
  alias Atlas.Accounts.POCs.POC
  alias Atlas.Users.User

  defp user do
    %User{}
    |> User.changeset(%{
      email: "pocs-#{System.unique_integer([:positive])}@tuist.dev",
      name: "POC Owner"
    })
    |> Repo.insert!()
  end

  defp account do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "account:#{suffix}",
      name: "Account #{suffix}",
      segment: :prospect
    })
    |> Repo.insert!()
  end

  defp feature_interest do
    suffix = System.unique_integer([:positive])

    %FeatureInterest{}
    |> FeatureInterest.changeset(%{
      title: "Feature #{suffix}",
      canonical_title: "feature-#{suffix}",
      status: "open"
    })
    |> Repo.insert!()
  end

  describe "create_poc/2" do
    test "creates a POC scoped to an account and records the actor" do
      user = user()
      account = account()

      assert {:ok, poc} =
               POCs.create_poc(
                 %{"account_id" => account.id, "title" => "Mobile evaluation", "hosting" => "cloud"},
                 user
               )

      assert poc.account_id == account.id
      assert poc.title == "Mobile evaluation"
      assert poc.hosting == "cloud"
      assert poc.status == "draft"
      assert poc.created_by_user_id == user.id
      assert poc.updated_by_user_id == user.id
      assert is_nil(poc.public_token)
    end

    test "rejects when no user is authenticated" do
      assert {:error, :unauthorized} =
               POCs.create_poc(%{"account_id" => account().id, "title" => "x"}, nil)
    end

    test "rejects when end date is before start date" do
      account = account()

      assert {:error, changeset} =
               POCs.create_poc(
                 %{
                   "account_id" => account.id,
                   "title" => "x",
                   "starts_on" => "2026-02-01",
                   "ends_on" => "2026-01-15"
                 },
                 user()
               )

      assert %{ends_on: [_]} = errors_on(changeset)
    end
  end

  describe "publish_poc/2" do
    test "mints a stable public token that can round-trip through lookup" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)

      assert {:ok, published} = POCs.publish_poc(poc, user)
      assert is_binary(published.public_token)

      fetched = POCs.get_poc_by_public_token(published.public_token)
      assert fetched.id == poc.id

      # Idempotent: publishing an already-published POC returns the same token.
      assert {:ok, ^published} = POCs.publish_poc(published, user)
    end

    test "rotate_public_token replaces the token and invalidates the old link" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)
      {:ok, published} = POCs.publish_poc(poc, user)

      assert {:ok, rotated} = POCs.rotate_public_token(published, user)
      assert rotated.public_token != published.public_token
      assert POCs.get_poc_by_public_token(published.public_token) == nil
      assert POCs.get_poc_by_public_token(rotated.public_token).id == poc.id
    end

    test "unpublish clears the token" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)
      {:ok, published} = POCs.publish_poc(poc, user)

      assert {:ok, cleared} = POCs.unpublish_poc(published, user)
      assert is_nil(cleared.public_token)
      assert POCs.get_poc_by_public_token(published.public_token) == nil
    end
  end

  describe "upsert_context/3" do
    test "captures hosting model, developer count, and CI on the context row" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)

      assert {:ok, context} =
               POCs.upsert_context(
                 poc,
                 %{
                   "developer_count" => 42,
                   "ci_solution" => "github_actions",
                   "git_forge" => "github",
                   "monorepo" => true
                 },
                 user
               )

      assert context.poc_id == poc.id
      assert context.developer_count == 42
      assert context.ci_solution == "github_actions"

      # Second call updates the same row instead of inserting a duplicate.
      assert {:ok, updated} =
               POCs.upsert_context(poc, %{"developer_count" => 60}, user)

      assert updated.id == context.id
      assert updated.developer_count == 60
    end
  end

  describe "scope features" do
    test "add_scope_feature attaches an existing feature interest exactly once" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)
      feature = feature_interest()

      assert {:ok, _scope_feature} = POCs.add_scope_feature(poc, feature.id, user)
      assert {:error, changeset} = POCs.add_scope_feature(poc, feature.id, user)
      assert %{poc_id: [_]} = errors_on(changeset)
    end

    test "remove_scope_feature detaches the join and preserves the feature interest" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)
      feature = feature_interest()
      {:ok, _} = POCs.add_scope_feature(poc, feature.id, user)

      assert {:ok, _} = POCs.remove_scope_feature(poc, feature.id, user)
      assert Repo.get(FeatureInterest, feature.id)
    end
  end

  describe "timeline entries" do
    test "add_timeline_entry stamps the actor label when the user has a name" do
      user = user()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC"}, user)

      assert {:ok, entry} =
               POCs.add_timeline_entry(
                 poc,
                 %{
                   "occurred_on" => "2026-06-01",
                   "title" => "Kickoff",
                   "kind" => "milestone"
                 },
                 user
               )

      assert entry.title == "Kickoff"
      assert entry.kind == "milestone"
      assert entry.author_label == user.name
      assert entry.created_by_user_id == user.id
    end

    test "delete_timeline_entry only removes entries that belong to the POC" do
      user = user()
      {:ok, poc_a} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC A"}, user)
      {:ok, poc_b} = POCs.create_poc(%{"account_id" => account().id, "title" => "POC B"}, user)

      {:ok, entry_in_a} =
        POCs.add_timeline_entry(
          poc_a,
          %{"occurred_on" => "2026-06-01", "title" => "In A"},
          user
        )

      assert {:error, :not_found} = POCs.delete_timeline_entry(poc_b, entry_in_a, user)
      assert {:ok, _} = POCs.delete_timeline_entry(poc_a, entry_in_a, user)
    end
  end

  describe "list_pocs/1" do
    test "filters by account_id and by status" do
      user = user()
      account_a = account()
      account_b = account()

      {:ok, _} = POCs.create_poc(%{"account_id" => account_a.id, "title" => "A1"}, user)
      {:ok, poc_a2} = POCs.create_poc(%{"account_id" => account_a.id, "title" => "A2"}, user)
      {:ok, _} = POCs.create_poc(%{"account_id" => account_b.id, "title" => "B1"}, user)

      {:ok, _} = POCs.update_poc(poc_a2, %{"status" => "active"}, user)

      assert Enum.count(POCs.list_pocs(account_id: account_a.id)) == 2
      assert Enum.count(POCs.list_pocs(account_id: account_b.id)) == 1

      active_ids = POCs.list_pocs(status: "active") |> Enum.map(& &1.id)
      assert poc_a2.id in active_ids
    end
  end

  describe "get_poc_by_public_token/1" do
    test "returns nil for an unknown token" do
      assert POCs.get_poc_by_public_token(Ecto.UUID.generate()) == nil
    end

    test "returns nil for a malformed token without raising" do
      assert POCs.get_poc_by_public_token("not-a-uuid") == nil
    end
  end

  describe "%POC{}" do
    test "public?/1 is true only when a token is present" do
      refute POC.public?(%POC{public_token: nil})
      assert POC.public?(%POC{public_token: Ecto.UUID.generate()})
    end
  end

  describe "verify_access_email/2" do
    defp published_poc_for_access do
      user = user()
      account = account()
      {:ok, poc} = POCs.create_poc(%{"account_id" => account.id, "title" => "POC"}, user)
      {:ok, published} = POCs.publish_poc(poc, user)
      published
    end

    test "accepts a valid token before the verification window expires" do
      poc = published_poc_for_access()

      {:ok, _request, token} =
        POCs.create_access_request(poc, "jordan@example.com", ip: nil, user_agent: nil)

      assert {:ok, %AccessRequest{verified_at: %DateTime{}}} =
               POCs.verify_access_email(
                 hd(POCs.list_access_requests(poc)).id,
                 token
               )
    end

    test "rejects a token whose verification window has expired even when the session is still valid" do
      poc = published_poc_for_access()

      {:ok, request, token} =
        POCs.create_access_request(poc, "jordan@example.com", ip: nil, user_agent: nil)

      # Push the verification deadline into the past while leaving the (much
      # longer) session `expires_at` untouched. Regression guard: the two
      # clocks used to be the same field, so an old link stayed valid for
      # up to 30 days.
      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

      Atlas.Repo.update_all(
        Ecto.Query.from(r in AccessRequest, where: r.id == ^request.id),
        set: [verification_expires_at: past]
      )

      assert {:error, :invalid_token} = POCs.verify_access_email(request.id, token)
    end
  end
end
