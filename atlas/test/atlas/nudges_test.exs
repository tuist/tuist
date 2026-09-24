defmodule Atlas.NudgesTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Audit.Activity
  alias Atlas.GTM.Delivery
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
    test "prefers a decision maker over primary and plain contacts" do
      account = insert_account!()
      _plain = insert_contact!(account, %{email: "plain@example.com", full_name: "A"})
      _primary = insert_contact!(account, %{email: "primary@example.com", full_name: "B", is_primary: true})

      decision_maker =
        insert_contact!(account, %{
          email: "boss@example.com",
          full_name: "C",
          is_decision_maker: true
        })

      assert %Contact{id: id, email: "boss@example.com"} = Nudges.select_contact_for(account)
      assert id == decision_maker.id
    end

    test "prefers a primary contact when no decision maker exists" do
      account = insert_account!()
      _plain = insert_contact!(account, %{email: "plain@example.com", full_name: "A"})
      primary = insert_contact!(account, %{email: "primary@example.com", full_name: "B", is_primary: true})

      assert %Contact{id: id, email: "primary@example.com"} = Nudges.select_contact_for(account)
      assert id == primary.id
    end

    test "falls back to insert order when no priority flag is set" do
      account = insert_account!()
      picked = insert_contact!(account, %{email: "picked@example.com", full_name: "A"})
      _second = insert_contact!(account, %{email: "second@example.com", full_name: "B"})

      assert %Contact{id: id, email: "picked@example.com"} = Nudges.select_contact_for(account)
      assert id == picked.id
    end

    test "excludes bounced and opted-out contacts even when they carry priority flags" do
      account = insert_account!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      insert_contact!(account, %{
        email: "bounced@example.com",
        full_name: "A",
        is_decision_maker: true,
        bounced_at: now
      })

      insert_contact!(account, %{
        email: "opted-out@example.com",
        full_name: "B",
        is_primary: true,
        opted_out_at: now
      })

      good = insert_contact!(account, %{email: "good@example.com", full_name: "C"})

      assert %Contact{id: id, email: "good@example.com"} = Nudges.select_contact_for(account)
      assert id == good.id
    end

    test "returns nil when the account has no reachable contact" do
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

  describe "send/2" do
    test "queues a delivery, transitions to sent, records immutable audit" do
      account = insert_account!()
      user = insert_user!()
      contact = insert_contact!(account, %{email: "primary@example.com", is_primary: true})

      {:ok, claimed} = claim_nudge_with_contact(account, user, contact)

      assert {:ok, %Nudge{state: "sent", sent_at: sent_at, email_delivery_id: delivery_id} = nudge} =
               Nudges.send(claimed.id, user)

      assert sent_at
      assert delivery_id
      assert nudge.duplicate == false

      delivery = Repo.get!(Delivery, delivery_id)
      assert delivery.recipient_email == "primary@example.com"
      assert delivery.subject == claimed.draft_subject

      assert Activity
             |> Atlas.Repo.all()
             |> Enum.any?(&(&1.action == "nudge.sent" and &1.target_id == nudge.id))
    end

    test "collapses to sent with duplicate=true when the same subject+body is queued twice" do
      account = insert_account!()
      user = insert_user!()
      contact = insert_contact!(account, %{email: "dup@example.com"})
      {:ok, first_claimed} = claim_nudge_with_contact(account, user, contact)

      {:ok, _first} = Nudges.send(first_claimed.id, user)

      # Second nudge with the same draft to the same recipient.
      {:ok, second_claimed} = claim_nudge_with_contact(account, user, contact, "k2")

      assert {:ok, %Nudge{state: "sent", duplicate: true}} =
               Nudges.send(second_claimed.id, user)
    end

    test "rejects when the actor is neither claimant nor holds admin:write" do
      account = insert_account!()
      owner = insert_user!()
      intruder = insert_user!()
      contact = insert_contact!(account, %{email: "target@example.com"})

      {:ok, claimed} = claim_nudge_with_contact(account, owner, contact)

      assert {:error, :not_authorized} = Nudges.send(claimed.id, intruder)
    end

    test "allows an admin:write user who is not the claimant to send" do
      account = insert_account!()
      owner = insert_user!()
      admin = insert_user!(%{role: :executive})
      contact = insert_contact!(account, %{email: "target@example.com"})

      {:ok, claimed} = claim_nudge_with_contact(account, owner, contact)

      assert {:ok, %Nudge{state: "sent"}} = Nudges.send(claimed.id, admin)
    end

    test "rejects when the nudge is not claimed" do
      account = insert_account!()
      admin = insert_user!(%{role: :executive})
      contact = insert_contact!(account, %{email: "target@example.com"})
      {:ok, proposed} = propose_with_contact(account, contact)

      # Admin bypasses the claimant check, so we hit the state gate cleanly.
      assert {:error, {:invalid_state, "pending_post"}} =
               Nudges.send(proposed.id, admin)
    end

    test "rejects when the contact has been bounced since the nudge was created" do
      account = insert_account!()
      user = insert_user!()
      contact = insert_contact!(account, %{email: "target@example.com"})
      {:ok, claimed} = claim_nudge_with_contact(account, user, contact)

      contact
      |> Ecto.Changeset.change(bounced_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      assert {:error, :contact_bounced} = Nudges.send(claimed.id, user)
    end
  end

  describe "retry/1" do
    test "moves a sent nudge with a failed delivery back to claimed" do
      account = insert_account!()
      user = insert_user!()
      contact = insert_contact!(account, %{email: "target@example.com"})
      {:ok, claimed} = claim_nudge_with_contact(account, user, contact)
      {:ok, sent} = Nudges.send(claimed.id, user)

      # In Oban :testing :manual, the delivery worker is enqueued as
      # `available`. Retry only fires once no active job remains; delete it
      # to simulate an exhausted retry loop.
      Ecto.Adapters.SQL.query!(
        Repo,
        "DELETE FROM oban_jobs WHERE worker = $1 AND args->>'delivery_id' = $2",
        ["Atlas.GTM.Workers.DeliverDirectEmail", sent.email_delivery_id]
      )

      Repo.get!(Delivery, sent.email_delivery_id)
      |> Ecto.Changeset.change(status: "failed")
      |> Repo.update!()

      assert {:ok, %Nudge{state: "claimed", email_delivery_id: nil}} = Nudges.retry(sent.id)
    end

    test "refuses when the delivery is still retrying at the Oban level" do
      account = insert_account!()
      user = insert_user!()
      contact = insert_contact!(account, %{email: "target@example.com"})
      {:ok, claimed} = claim_nudge_with_contact(account, user, contact)
      {:ok, sent} = Nudges.send(claimed.id, user)

      # Delivery failed but a live Oban job is scheduled to retry.
      delivery_id = sent.email_delivery_id

      Repo.get!(Delivery, delivery_id)
      |> Ecto.Changeset.change(status: "failed")
      |> Repo.update!()

      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO oban_jobs (state, queue, worker, args, attempt, max_attempts, inserted_at, scheduled_at)
        VALUES ('retryable', 'mailing', $1, $2::jsonb, 1, 5, now(), now())
        """,
        ["Atlas.GTM.Workers.DeliverDirectEmail", ~s({"delivery_id":"#{delivery_id}"})]
      )

      assert {:error, {:retry_not_allowed, :retrying}} = Nudges.retry(sent.id)
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

  defp claim_nudge_with_contact(account, user, contact, key \\ "k1") do
    {:ok, nudge} = propose_with_contact(account, contact, key)
    {:ok, posted} = Nudges.mark_nudge_posted(nudge, "C-CHAN", "1700000000.#{key}")
    Nudges.claim(posted.id, user)
  end

  defp propose_with_contact(account, contact, key \\ "k1") do
    Nudges.propose(account, "invited_teammates_sso", %{proposal(key) | contact_id: contact.id})
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
    {priority_attrs, base_attrs} =
      Map.split(attrs, [:is_primary, :is_decision_maker, :bounced_at, :opted_out_at])

    defaults = %{
      full_name: "Contact #{System.unique_integer([:positive])}",
      email: "contact-#{System.unique_integer([:positive])}@example.com",
      account_id: account.id
    }

    contact =
      %Contact{}
      |> Contact.changeset(Map.merge(defaults, base_attrs))
      |> Repo.insert!()

    case priority_attrs do
      empty when map_size(empty) == 0 ->
        contact

      changes ->
        contact
        |> Ecto.Changeset.change(changes)
        |> Repo.update!()
    end
  end

  defp insert_user!(attrs \\ %{}) do
    {role, scopes, attrs} = AtlasWeb.ConnCase.extract_role_and_scopes(attrs)

    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    user =
      %User{}
      |> User.changeset(Map.merge(defaults, attrs))
      |> Repo.insert!()

    AtlasWeb.ConnCase.assign_role_or_scopes(user, role, scopes)
    user
  end
end
