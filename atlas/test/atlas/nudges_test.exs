defmodule Atlas.NudgesTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Nudges
  alias Atlas.Nudges.Nudge
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.SignalEpisode
  alias Atlas.Repo
  alias Atlas.Users.User

  describe "open_or_touch_episode/3" do
    test "opens a fresh episode and returns :existing on the second call" do
      account = insert_account!()

      assert {:opened, %SignalEpisode{state: "open"} = episode} =
               Nudges.open_or_touch_episode(account, "invited_teammates_sso", %{"n" => 5})

      assert {:existing, %SignalEpisode{id: id}} =
               Nudges.open_or_touch_episode(account, "invited_teammates_sso", %{"n" => 6})

      assert id == episode.id
    end
  end

  describe "close_episode/2" do
    test "closes the open episode; a no-op if none exists" do
      account = insert_account!()
      assert :ok = Nudges.close_episode(account, "invited_teammates_sso")

      assert {:opened, _} = Nudges.open_or_touch_episode(account, "invited_teammates_sso")
      assert :ok = Nudges.close_episode(account, "invited_teammates_sso")

      episode = Repo.get_by!(SignalEpisode, signal: "invited_teammates_sso", account_id: account.id)
      assert episode.state == "closed"
      assert episode.closed_at
    end
  end

  describe "propose/3" do
    test "inserts a pending_post nudge with the signal, dedup key, and draft" do
      account = insert_account!()
      _contact = insert_contact!(account)

      assert {:ok, %Nudge{state: "pending_post"} = nudge} =
               Nudges.propose(account, "invited_teammates_sso", proposal("k1"))

      assert nudge.signal == "invited_teammates_sso"
      assert nudge.dedup_key == "k1"
      assert nudge.draft_subject != ""
      assert nudge.expires_at
    end

    test "skips as :duplicate when an open nudge with the same dedup key already exists" do
      account = insert_account!()
      {:ok, _first} = Nudges.propose(account, "invited_teammates_sso", proposal("k1"))

      assert {:skip, :duplicate} =
               Nudges.propose(account, "invited_teammates_sso", proposal("k1"))
    end

    test "allows a second nudge with a different dedup key" do
      account = insert_account!()
      {:ok, _first} = Nudges.propose(account, "invited_teammates_sso", proposal("k1"))

      assert {:ok, %Nudge{}} =
               Nudges.propose(account, "invited_teammates_sso", proposal("k2"))
    end

    test "enforces the per-account open-nudge rate limit" do
      account = insert_account!()

      {:ok, _} = Nudges.propose(account, "s", proposal("a"))
      {:ok, _} = Nudges.propose(account, "s", proposal("b"))
      {:ok, _} = Nudges.propose(account, "s", proposal("c"))

      assert {:skip, :rate_limited} = Nudges.propose(account, "s", proposal("d"))
    end
  end

  describe "select_contact_for/1" do
    test "picks the first contact with a non-empty email, sorted by insert time" do
      account = insert_account!()
      picked = insert_contact!(account, %{email: "picked@example.com", full_name: "A"})
      _second = insert_contact!(account, %{email: "second@example.com", full_name: "B"})

      assert %Contact{id: id, email: "picked@example.com"} = Nudges.select_contact_for(account)
      assert id == picked.id
    end

    test "returns nil when the account has no contacts with an email" do
      account = insert_account!()
      assert nil == Nudges.select_contact_for(account)
    end
  end

  describe "claim/2, release/1, dismiss/2" do
    test "claim + release round-trip under a row lock" do
      account = insert_account!()
      user = insert_user!()

      {:ok, nudge} = Nudges.propose(account, "s", proposal("k1"))
      {:ok, posted} = Nudges.mark_nudge_posted(nudge, "C-CHAN", "1700000000.001")

      assert {:ok, %Nudge{state: "claimed", claimed_by_user_id: claimed_by, claimed_at: claimed_at}} =
               Nudges.claim(posted.id, user)

      assert claimed_by == user.id
      assert claimed_at

      assert {:ok, %Nudge{state: "proposed", claimed_by_user_id: nil, claimed_at: nil}} =
               Nudges.release(posted.id)
    end

    test "dismiss requires a reason and records it" do
      account = insert_account!()
      {:ok, nudge} = Nudges.propose(account, "s", proposal("k1"))
      {:ok, posted} = Nudges.mark_nudge_posted(nudge, "C-CHAN", "1700000000.002")

      assert {:ok, %Nudge{state: "dismissed", dismissed_reason: "Not now"}} =
               Nudges.dismiss(posted.id, %{dismissed_reason: "Not now"})
    end
  end

  describe "expire_stale/1" do
    test "flips open nudges past expires_at into 'expired'" do
      account = insert_account!()
      {:ok, expiring} = Nudges.propose(account, "s", proposal("k1"))
      {:ok, still_open} = Nudges.propose(account, "s", proposal("k2"))

      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      Ecto.Adapters.SQL.query!(Repo, "UPDATE account_nudges SET expires_at = $1 WHERE id = $2", [
        DateTime.to_naive(past),
        Ecto.UUID.dump!(expiring.id)
      ])

      assert [%Nudge{id: expired_id, state: "expired"}] = Nudges.expire_stale()
      assert expired_id == expiring.id

      assert %Nudge{state: "pending_post"} = Repo.get!(Nudge, still_open.id)
    end
  end

  defp proposal(key) do
    %Proposal{
      dedup_key: key,
      title: "Reach out about #{key}",
      rationale: "Because #{key}",
      draft_subject: "Hello",
      draft_body: "Hi there,",
      evidence: %{"k" => key}
    }
  end

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account #{System.unique_integer([:positive])}",
      segment: :customer,
      plan_tier: "pro"
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_contact!(account, attrs \\ %{}) do
    defaults = %{
      full_name: "Contact #{System.unique_integer([:positive])}",
      email: "contact-#{System.unique_integer([:positive])}@example.com",
      account_id: account.id
    }

    %Contact{}
    |> Contact.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_user!(attrs \\ %{}) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
