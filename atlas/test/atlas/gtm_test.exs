defmodule Atlas.GTMTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.OpportunityContact
  alias Atlas.GTM.SignalQuery
  alias Atlas.GTM.SocialChannelIdea
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.GTM.Workers.PostBlogPostIdeaAnnouncement
  alias Atlas.Search.Record, as: SearchRecord
  alias Atlas.Slack.API
  alias Atlas.Users.User

  setup :verify_on_exit!

  defp insert_user!(email) do
    %User{}
    |> User.changeset(%{email: email, name: "Atlas User"})
    |> Repo.insert!()
  end

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :prospect
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp signal_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        company_name: "Acme Platforms",
        company_key: "domain:acme.example",
        domain: "acme.example",
        source: "brave",
        source_ref: "https://acme.example/blog/ios-ci",
        source_url: "https://acme.example/blog/ios-ci",
        title: "How Acme scales iOS CI with Swift modules",
        excerpt: "Xcode build times and developer productivity work for a large mobile CI setup.",
        matched_terms: ["iOS", "Swift", "Xcode", "monorepo", "developer productivity"],
        signal_kind: "engineering_blog",
        confidence: 82,
        observed_at: ~U[2026-06-01 12:00:00Z],
        metadata: %{"query" => "iOS Swift monorepo"}
      },
      overrides
    )
  end

  describe "create_blog_post_idea/2" do
    test "creates an idea, trims fields, and records the author" do
      author = insert_user!("author@example.com")

      {:ok, idea} =
        GTM.create_blog_post_idea(
          %{"title" => "  Scaling CI with Tuist  ", "description" => "  An angle  ", "status" => "idea"},
          author
        )

      assert idea.title == "Scaling CI with Tuist"
      assert idea.description == "An angle"
      assert idea.status == "idea"
      assert idea.author_id == author.id
    end

    test "defaults status to idea and allows a nil author" do
      {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Idea without author"})

      assert idea.status == "idea"
      assert idea.author_id == nil
    end

    test "rejects a blank title" do
      assert {:error, changeset} = GTM.create_blog_post_idea(%{"title" => "   "})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an unknown status" do
      assert {:error, changeset} =
               GTM.create_blog_post_idea(%{"title" => "Bad status", "status" => "archived"})

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "does not announce to Slack by default" do
      {:ok, _idea} = GTM.create_blog_post_idea(%{"title" => "Quiet idea"})
      refute_enqueued(worker: PostBlogPostIdeaAnnouncement)
    end

    test "enqueues a Slack announcement when announce: true" do
      {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Loud idea"}, nil, announce: true)
      assert_enqueued(worker: PostBlogPostIdeaAnnouncement, args: %{"blog_post_idea_id" => idea.id})
    end

    test "does not announce when the idea is invalid" do
      assert {:error, _changeset} = GTM.create_blog_post_idea(%{"title" => "   "}, nil, announce: true)
      refute_enqueued(worker: PostBlogPostIdeaAnnouncement)
    end
  end

  describe "Slack thread association" do
    test "stores and looks up the announced thread" do
      {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Threaded"})

      {:ok, idea} = GTM.set_blog_post_idea_slack_thread(idea, "1717400000.000100")
      assert idea.slack_thread_ts == "1717400000.000100"

      found = GTM.get_blog_post_idea_by_slack_thread("1717400000.000100")
      assert found.id == idea.id

      assert GTM.get_blog_post_idea_by_slack_thread("9999.0000") == nil
    end
  end

  describe "list_blog_post_ideas/0" do
    test "orders by status then recency and preloads comments" do
      {:ok, published} = GTM.create_blog_post_idea(%{"title" => "Published", "status" => "published"})
      {:ok, fresh_idea} = GTM.create_blog_post_idea(%{"title" => "Fresh idea", "status" => "idea"})
      {:ok, _comment} = GTM.create_blog_post_idea_comment(fresh_idea, %{"body" => "first"})

      ideas = GTM.list_blog_post_ideas()

      assert Enum.map(ideas, & &1.title) == ["Fresh idea", "Published"]
      assert [%{title: "Fresh idea", comments: [_one]} | _] = ideas
      assert published.id in Enum.map(ideas, & &1.id)
    end
  end

  describe "get_blog_post_idea/1" do
    test "preloads ordered comments with their authors" do
      author = insert_user!("commenter@example.com")
      {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "With comments"})
      {:ok, _} = GTM.create_blog_post_idea_comment(idea, %{"body" => "earliest"}, author)
      {:ok, _} = GTM.create_blog_post_idea_comment(idea, %{"body" => "latest"})

      loaded = GTM.get_blog_post_idea(idea.id)

      assert Enum.map(loaded.comments, & &1.body) == ["earliest", "latest"]
      assert [%{author: %{email: "commenter@example.com"}} | _] = loaded.comments
    end

    test "returns nil for an unknown idea" do
      assert GTM.get_blog_post_idea(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_blog_post_idea/2" do
    test "updates the status" do
      {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Movable"})

      assert {:ok, updated} = GTM.update_blog_post_idea(idea, %{"status" => "in_progress"})
      assert updated.status == "in_progress"
    end
  end

  describe "create_blog_post_idea_comment/3" do
    test "rejects a blank comment" do
      {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Has thread"})

      assert {:error, changeset} = GTM.create_blog_post_idea_comment(idea, %{"body" => "   "})
      assert %{body: _} = errors_on(changeset)
    end
  end

  test "statuses/0 exposes the allowed statuses" do
    assert BlogPostIdea.statuses() == ~w(idea in_progress published)
  end

  describe "create_social_channel_idea/2" do
    test "creates an idea, trims fields, and records the author" do
      author = insert_user!("social-author@example.com")

      {:ok, idea} =
        GTM.create_social_channel_idea(
          %{
            "title" => "  Share the benchmark chart  ",
            "description" => "  Short post angle  ",
            "status" => "approved"
          },
          author
        )

      assert idea.title == "Share the benchmark chart"
      assert idea.description == "Short post angle"
      assert idea.status == "approved"
      assert idea.author_id == author.id
    end

    test "rejects a blank title and unknown status" do
      assert {:error, changeset} = GTM.create_social_channel_idea(%{"title" => "   "})
      assert %{title: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               GTM.create_social_channel_idea(%{"title" => "Bad status", "status" => "scheduled"})

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_social_channel_ideas/0" do
    test "orders by status then recency and preloads authors" do
      author = insert_user!("social-list@example.com")
      {:ok, published} = GTM.create_social_channel_idea(%{"title" => "Published", "status" => "approved"})
      {:ok, _fresh} = GTM.create_social_channel_idea(%{"title" => "Fresh", "status" => "idea"}, author)

      ideas = GTM.list_social_channel_ideas()

      assert Enum.map(ideas, & &1.title) == ["Fresh", "Published"]
      assert [%{title: "Fresh", author: %{email: "social-list@example.com"}} | _] = ideas
      assert published.id in Enum.map(ideas, & &1.id)
    end
  end

  describe "get_social_channel_idea/1" do
    test "preloads the author and returns nil for unknown ideas" do
      author = insert_user!("social-get@example.com")
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "With author"}, author)

      loaded = GTM.get_social_channel_idea(idea.id)

      assert loaded.author.email == "social-get@example.com"
      assert GTM.get_social_channel_idea(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_social_channel_idea/2" do
    test "updates the status and description" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Movable social"})

      assert {:ok, updated} =
               GTM.update_social_channel_idea(idea, %{
                 "status" => "approved",
                 "description" => "Ready to publish."
               })

      assert updated.status == "approved"
      assert updated.description == "Ready to publish."
    end
  end

  describe "delete_social_channel_idea/1" do
    test "deletes the idea and its search record" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Delete social idea"})

      assert Repo.get_by(SearchRecord, source_type: "social_channel_idea", source_id: idea.id)

      assert {:ok, deleted} = GTM.delete_social_channel_idea(idea)
      assert deleted.id == idea.id

      refute Repo.get(SocialChannelIdea, idea.id)
      refute Repo.get_by(SearchRecord, source_type: "social_channel_idea", source_id: idea.id)
    end
  end

  test "social statuses/0 exposes the allowed statuses" do
    assert SocialChannelIdea.statuses() == ~w(idea approved)
  end

  describe "social post revisions" do
    test "creates ordered revisions and preloads them on the parent idea" do
      author = insert_user!("social-revision-author@example.com")
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Revision thread"}, author)

      assert {:ok, first} =
               GTM.create_social_post_revision(
                 idea,
                 %{"body" => "  First post draft  ", "notes" => "  Initial pass  "},
                 author
               )

      assert {:ok, second} =
               GTM.create_social_post_revision(
                 idea,
                 %{"body" => "Second post draft"},
                 author
               )

      assert first.revision_number == 1
      assert first.body == "First post draft"
      assert first.notes == "Initial pass"
      assert second.revision_number == 2

      loaded = GTM.get_social_channel_idea(idea.id)
      assert Enum.map(loaded.post_revisions, & &1.revision_number) == [1, 2]
      assert [%{author: %{email: "social-revision-author@example.com"}} | _] = loaded.post_revisions
    end

    test "publishes one revision and syncs the parent idea status" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Publish a revision"})
      {:ok, first} = GTM.create_social_post_revision(idea, %{"body" => "First published", "status" => "approved"})
      {:ok, second} = GTM.create_social_post_revision(idea, %{"body" => "Second draft"})

      assert GTM.get_social_channel_idea(idea.id).status == "approved"

      assert {:ok, published_second} = GTM.approve_social_post_revision(second)
      assert published_second.status == "approved"
      assert Repo.get!(SocialPostRevision, first.id).status == "draft"
      assert GTM.get_social_channel_idea(idea.id).status == "approved"
    end

    test "editing an approved revision's body leaves its sibling revisions untouched" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Edit published body"})
      {:ok, first} = GTM.create_social_post_revision(idea, %{"body" => "First draft"})
      {:ok, second} = GTM.create_social_post_revision(idea, %{"body" => "Second", "status" => "approved"})

      # Backdate the sibling so a spurious re-draft would show up as a bumped updated_at.
      past = ~N[2020-01-01 00:00:00]

      {1, _} =
        SocialPostRevision
        |> where([revision], revision.id == ^first.id)
        |> Repo.update_all(set: [updated_at: past])

      assert {:ok, updated} = GTM.update_social_post_revision(second, %{"body" => "Second, edited"})
      assert updated.status == "approved"
      assert updated.body == "Second, edited"

      first_after = Repo.get!(SocialPostRevision, first.id)
      assert first_after.status == "draft"
      assert NaiveDateTime.compare(first_after.updated_at, past) == :eq
    end

    test "deleting the approved revision returns the parent idea to idea status" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Delete published revision"})
      {:ok, revision} = GTM.create_social_post_revision(idea, %{"body" => "Published post", "status" => "approved"})

      assert {:ok, _deleted} = GTM.delete_social_post_revision(revision)

      refute Repo.get(SocialPostRevision, revision.id)
      assert GTM.get_social_channel_idea(idea.id).status == "idea"
    end

    test "adding a draft revision does not unapprove a manually approved idea" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Manual published", "status" => "approved"})

      assert {:ok, _revision} = GTM.create_social_post_revision(idea, %{"body" => "Draft iteration"})

      assert GTM.get_social_channel_idea(idea.id).status == "approved"
    end

    test "rejects blank bodies and invalid statuses" do
      {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Invalid revision"})

      assert {:error, changeset} = GTM.create_social_post_revision(idea, %{"body" => "   "})
      assert %{body: _} = errors_on(changeset)

      assert {:error, changeset} =
               GTM.create_social_post_revision(idea, %{"body" => "Draft", "status" => "queued"})

      assert %{status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "GTM outreach opportunities" do
    test "curated research queries focus on iOS and Swift instead of Bazel" do
      %SignalQuery{}
      |> SignalQuery.changeset(%{
        name: "Legacy Bazel query",
        source: "brave",
        query: ~s("Bazel" "monorepo"),
        metadata: %{"topic_source" => "curated", "topic" => "Build systems"}
      })
      |> Repo.insert!()

      assert {:ok, queries} = GTM.ensure_research_signal_queries()

      query_text = queries |> Enum.map_join(" ", & &1.query)

      assert query_text =~ "iOS"
      assert query_text =~ "Swift"
      refute String.downcase(query_text) =~ "bazel"
      assert [] = GTM.list_signal_queries(enabled?: true) |> Enum.filter(&(&1.name == "Legacy Bazel query"))
    end

    test "curated research queries include Tuist public mention discovery" do
      assert {:ok, queries} = GTM.ensure_research_signal_queries()

      assert Enum.any?(queries, fn query ->
               query.name == "Tuist developer posts" and
                 query.source == "brave" and
                 query.metadata["topic"] == "Tuist mentions"
             end)

      assert Enum.any?(queries, fn query ->
               query.name == "Tuist project files" and
                 query.source == "github" and
                 query.query == "Tuist filename:Project.swift"
             end)
    end

    test "records signals, dedupes by source ref, and scores the opportunity" do
      assert {:ok, signal} = GTM.record_gtm_signal(signal_attrs())
      assert {:ok, updated_signal} = GTM.record_gtm_signal(signal_attrs(%{excerpt: "Updated excerpt"}))

      assert signal.id == updated_signal.id

      [opportunity] = GTM.list_gtm_opportunities()
      assert opportunity.company_name == "Acme Platforms"
      assert opportunity.domain == "acme.example"
      assert opportunity.score > 0
      assert opportunity.signal_summary =~ "Swift"
      assert length(opportunity.signals) == 1
    end

    test "opportunity changesets ignore account_id params" do
      account = insert_account!()

      changeset =
        Opportunity.changeset(%Opportunity{}, %{
          company_key: "domain:mass-assignment.example",
          company_name: "Mass Assignment",
          status: "new",
          score: 42,
          account_id: account.id
        })

      refute Ecto.Changeset.get_change(changeset, :account_id)

      assert {:ok, opportunity} = Repo.insert(changeset)
      assert opportunity.account_id == nil

      assert {:ok, updated} =
               GTM.update_gtm_opportunity_status(opportunity, "qualified", %{account_id: account.id})

      assert updated.status == "qualified"
      assert updated.account_id == nil
    end

    test "opportunity contact changeset requires opportunity_id on the struct" do
      {:ok, signal} = GTM.record_gtm_signal(signal_attrs())
      opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)

      attrs = %{
        title: "Head of Developer Experience",
        full_name: "Riley Stone",
        confidence: 88,
        opportunity_id: opportunity.id
      }

      assert %{opportunity_id: ["can't be blank"]} =
               %OpportunityContact{}
               |> OpportunityContact.changeset(attrs)
               |> errors_on()

      assert {:ok, contact} =
               %OpportunityContact{opportunity_id: opportunity.id}
               |> OpportunityContact.changeset(Map.delete(attrs, :opportunity_id))
               |> Repo.insert()

      assert contact.opportunity_id == opportunity.id
    end

    test "records public Tuist developer mentions as suggested contacts" do
      assert {:ok, signal} =
               GTM.record_gtm_signal(
                 signal_attrs(%{
                   company_name: "Acme Mobile",
                   company_key: "github-company:acme-mobile",
                   domain: nil,
                   source: "github",
                   source_ref: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
                   source_url: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
                   title: "mobiledev/ios-app: Project.swift",
                   matched_terms: ["Tuist", "Project.swift", "Swift", "iOS"],
                   signal_kind: "tuist_mention",
                   confidence: 95,
                   metadata: %{
                     "mention_type" => "tuist_public_mention",
                     "person" => %{
                       "login" => "mobiledev",
                       "name" => "Maya Singh",
                       "company" => "Acme Mobile",
                       "github_url" => "https://github.com/mobiledev",
                       "title" => "Public Tuist advocate",
                       "confidence" => 86
                     }
                   }
                 })
               )

      assert {:ok, _updated_signal} =
               GTM.record_gtm_signal(
                 signal_attrs(%{
                   company_name: "Acme Mobile",
                   company_key: "github-company:acme-mobile",
                   domain: nil,
                   source: "github",
                   source_ref: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
                   source_url: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
                   title: "mobiledev/ios-app: Project.swift",
                   matched_terms: ["Tuist", "Project.swift", "Swift", "iOS"],
                   signal_kind: "tuist_mention",
                   confidence: 95,
                   metadata: %{
                     "mention_type" => "tuist_public_mention",
                     "person" => %{
                       "login" => "mobiledev",
                       "name" => "Maya Singh",
                       "company" => "Acme Mobile",
                       "github_url" => "https://github.com/mobiledev",
                       "title" => "Public Tuist advocate",
                       "confidence" => 86
                     }
                   }
                 })
               )

      opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)

      assert opportunity.company_name == "Acme Mobile"

      assert [
               %{
                 source: "github",
                 full_name: "Maya Singh",
                 title: "Public Tuist advocate",
                 organization_name: "Acme Mobile"
               }
             ] = opportunity.contacts

      assert [advocate] = GTM.list_gtm_advocates()
      assert advocate.full_name == "Maya Singh"
      assert advocate.opportunity.company_name == "Acme Mobile"
      assert [%{signal_kind: "tuist_mention"}] = advocate.opportunity.signals

      assert {:ok, _opportunity} = GTM.update_gtm_opportunity_status(opportunity, "rejected")
      assert [] = GTM.list_gtm_advocates()
      assert [%{full_name: "Maya Singh"}] = GTM.list_gtm_advocates(status: "rejected")
    end

    test "enriches domainless opportunities by resolving the Apollo organization first" do
      {:ok, signal} =
        GTM.record_gtm_signal(
          signal_attrs(%{
            company_name: "Acme Mobile",
            company_key: "github-company:acme-mobile",
            domain: nil,
            source: "github",
            source_ref: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
            source_url: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
            title: "mobiledev/ios-app: Project.swift",
            matched_terms: ["Tuist", "Project.swift", "Swift", "iOS"],
            signal_kind: "tuist_mention",
            confidence: 95
          })
        )

      opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)

      request = fn request ->
        cond do
          String.ends_with?(request[:url], "/mixed_companies/search") ->
            assert request[:json].q_organization_name == "Acme Mobile"

            {:ok,
             %{
               status: 200,
               body: %{
                 "organizations" => [
                   %{"id" => "org_1", "name" => "Acme Mobile", "primary_domain" => "acme.example"}
                 ]
               }
             }}

          String.ends_with?(request[:url], "/mixed_people/api_search") ->
            assert request[:json].organization_ids == ["org_1"]

            {:ok,
             %{
               status: 200,
               body: %{
                 "people" => [
                   %{
                     "id" => "person_1",
                     "name" => "Nina Platform",
                     "title" => "Director Developer Productivity",
                     "organization" => %{"name" => "Acme Mobile", "id" => "org_1"},
                     "linkedin_url" => "https://linkedin.com/in/nina-platform",
                     "email" => "email_not_unlocked"
                   }
                 ]
               }
             }}
        end
      end

      assert {:ok, [contact]} =
               GTM.enrich_gtm_opportunity_contacts(opportunity, api_key: "apollo-key", request: request)

      assert contact.full_name == "Nina Platform"
      assert contact.organization_name == "Acme Mobile"
      assert contact.metadata["organization_id"] == "org_1"
      assert contact.metadata["organization_domain"] == "acme.example"
    end

    test "prepares high score opportunities by notifying Slack even when Apollo cannot enrich" do
      {:ok, signal} =
        GTM.record_gtm_signal(
          signal_attrs(%{
            title: "Acme scales iOS CI with Tuist and Xcode",
            excerpt: "iOS Swift Xcode monorepo platform mobile CI modules slow cache flaky reliability.",
            matched_terms: [
              "iOS",
              "Swift",
              "Xcode",
              "Tuist",
              "monorepo",
              "platform",
              "mobile",
              "CI",
              "slow",
              "cache"
            ],
            confidence: 95
          })
        )

      opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)
      assert opportunity.score >= 70

      expect(API, :post_message, fn :company, "C0AGV3YU8ET", text, blocks ->
        assert text =~ "Acme Platforms"
        assert is_list(blocks)
        {:ok, %{"ok" => true, "channel" => "C0AGV3YU8ET", "ts" => "1717400000.000100"}}
      end)

      assert {:ok, result} = GTM.prepare_gtm_opportunity_for_outreach(opportunity)
      assert result.contacts == []
      assert result.contact_error == :apollo_api_key_not_configured
      assert result.opportunity.slack_notification_channel_id == "C0AGV3YU8ET"
      assert result.opportunity.slack_notification_thread_ts == "1717400000.000100"
    end

    test "updates opportunity status and tracks review time" do
      {:ok, signal} = GTM.record_gtm_signal(signal_attrs())
      opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)

      assert {:ok, updated} = GTM.update_gtm_opportunity_status(opportunity, "qualified")
      assert updated.status == "qualified"
      assert %DateTime{} = updated.reviewed_at
    end

    test "converts an opportunity into a prospect account" do
      {:ok, signal} = GTM.record_gtm_signal(signal_attrs())
      opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)

      assert {:ok, account, converted} = GTM.convert_gtm_opportunity(opportunity)
      assert account.name == "Acme Platforms"
      assert account.primary_domain == "acme.example"
      assert account.segment == :prospect
      assert account.account_key == "gtm:acme-example"
      assert converted.status == "converted"
      assert converted.account_id == account.id
    end
  end
end
