# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

import Ecto.Query

alias Atlas.Accounts
alias Atlas.Accounts.Account
alias Atlas.Accounts.AccountAttentionSuggestion
alias Atlas.Accounts.AccountHandle
alias Atlas.Accounts.Amounts
alias Atlas.Accounts.Contact
alias Atlas.Accounts.Event
alias Atlas.Accounts.FeatureInterestAccount
alias Atlas.Accounts.Invoice
alias Atlas.Accounts.Outcome
alias Atlas.Accounts.OutcomeProposal
alias Atlas.Accounts.OutcomeReview
alias Atlas.Accounts.ServiceLevel
alias Atlas.Accounts.ServiceLevelExtractionCheck
alias Atlas.Accounts.ServiceLevels
alias Atlas.Accounts.Term
alias Atlas.Agents.Sessions.Event, as: AgentSessionEvent
alias Atlas.Agents.Sessions.Session, as: AgentSession
alias Atlas.Assets.Asset
alias Atlas.Assets.DataCenter
alias Atlas.Audit
alias Atlas.Briefs.Brief
alias Atlas.Briefs.BriefItem
alias Atlas.Briefs.Subscription, as: BriefSubscription
alias Atlas.Documents
alias Atlas.Documents.Document
alias Atlas.Engineering.Domains, as: EngineeringDomains
alias Atlas.Engineering.Domains.Domain, as: EngineeringDomain
alias Atlas.Engineering.Errors, as: EngineeringErrors
alias Atlas.Engineering.Errors.Issue, as: ErrorsIssue
alias Atlas.Engineering.Errors.SummaryRun, as: ErrorsSummaryRun
alias Atlas.Engineering.Postmortems
alias Atlas.Engineering.Projects, as: EngineeringProjects
alias Atlas.Engineering.Projects.Project, as: EngineeringProject
alias Atlas.Engineering.Specs
alias Atlas.Evidence
alias Atlas.FeatureUsage.Snapshot
alias Atlas.Finance.Account, as: FinanceAccount
alias Atlas.Finance.Category, as: FinanceCategory
alias Atlas.Finance.Invoice, as: FinanceInvoice
alias Atlas.Finance.InvoiceLineItem, as: FinanceInvoiceLineItem
alias Atlas.Finance.Source, as: FinanceSource
alias Atlas.Finance.Transaction, as: FinanceTransaction
alias Atlas.GTM
alias Atlas.GTM.Audience
alias Atlas.GTM.AudienceMembership
alias Atlas.GTM.BlogPostIdea
alias Atlas.GTM.BlogPostIdeaComment
alias Atlas.GTM.Broadcast
alias Atlas.GTM.Delivery
alias Atlas.GTM.OpportunityContact
alias Atlas.GTM.Signal, as: GTMSignal
alias Atlas.GTM.SocialChannelIdea
alias Atlas.GTM.SocialPostRevision
alias Atlas.GTM.Subscriber
alias Atlas.Inference
alias Atlas.Inference.ModelBinding
alias Atlas.Inference.Provider
alias Atlas.Insurance.Policy, as: InsurancePolicy
alias Atlas.Insurance.PolicyMember, as: InsuranceMember
alias Atlas.Integrations.GitHubApp
alias Atlas.Integrations.GitHubRepository
alias Atlas.Licenses.Issuer
alias Atlas.Licenses.License
alias Atlas.Memory
alias Atlas.Memory.Node, as: MemoryNode
alias Atlas.Notes
alias Atlas.Notes.Note
alias Atlas.Outreach
alias Atlas.Outreach.Candidate
alias Atlas.Outreach.Recommendation
alias Atlas.Product
alias Atlas.Product.Trace, as: ProductTrace
alias Atlas.Repo
alias Atlas.Slack.Channel, as: SlackChannel
alias Atlas.Slack.Message, as: SlackMessage
alias Atlas.Slack.User, as: SlackUser
alias Atlas.Support.Message, as: SupportMessage
alias Atlas.Support.Thread, as: SupportThread
alias Atlas.Users.User

seed_users = [
  %{email: "test@atlas.dev", name: "Test User", role: :executive},
  %{email: "alex@atlas.dev", name: "Alex Rivera", role: :executive},
  %{email: "morgan@atlas.dev", name: "Morgan Chen", role: :employee},
  %{email: "sam@atlas.dev", name: "Sam Okafor", role: :employee}
]

for attrs <- seed_users do
  case Repo.get_by(User, email: attrs.email) do
    nil -> %User{}
    existing -> existing
  end
  |> User.changeset(attrs)
  |> Repo.insert_or_update!()
end

seed_user = Repo.get_by!(User, email: "test@atlas.dev")

# Email audiences mirror the groups Atlas actively communicates with. Users
# represent the welcome-email audience populated by the product analytics
# destination. The rows are deliberately
# local-only examples and use atlas.dev addresses so development cannot target
# real recipients accidentally. Keep this near the top so the email dashboard
# remains useful even if an unrelated fixture later in this large seed file fails.
seed_email_audiences = [
  %{
    name: "Email Digest",
    slug: "email-digest",
    description: "Subscribers who opted in to receive the email digest.",
    source_id: "seed-tuist-digest-list"
  },
  %{
    name: "Enterprise incident contacts",
    slug: "enterprise-incident-contacts",
    description: "Operational and security contacts for enterprise incident communication."
  },
  %{
    name: "Users",
    slug: "users",
    description: "Product users eligible for the welcome email.",
    # The product analytics destination addresses audiences by the mailing list
    # id it used to send to Loops, which Atlas stores as the audience source id.
    source_id: "seed-posthog-signups-list"
  }
]

seeded_email_audiences =
  Map.new(seed_email_audiences, fn attrs ->
    audience = Repo.get_by(Audience, slug: attrs.slug) || %Audience{}

    audience =
      audience
      |> Audience.changeset(attrs)
      |> Repo.insert_or_update!()

    {attrs.slug, audience}
  end)

seed_email_subscribers = [
  %{
    email: "newsletter-reader@atlas.dev",
    first_name: "Taylor",
    last_name: "Reader",
    user_group: "developer",
    source: "loops-import",
    status: "subscribed",
    metadata: %{"seed" => true}
  },
  %{
    email: "enterprise-ops@atlas.dev",
    first_name: "Morgan",
    last_name: "Operations",
    user_group: "enterprise",
    source: "loops-import",
    status: "subscribed",
    metadata: %{"seed" => true}
  },
  %{
    email: "product-signup@atlas.dev",
    first_name: "Sam",
    last_name: "Builder",
    user_group: "developer",
    source: "posthog",
    status: "subscribed",
    metadata: %{"postHog" => true, "seed" => true},
    welcomed_at: ~U[2026-07-22 09:00:00Z]
  }
]

seeded_email_subscribers =
  Map.new(seed_email_subscribers, fn attrs ->
    subscriber = Repo.get_by(Subscriber, email: attrs.email) || %Subscriber{}

    subscriber =
      subscriber
      |> Subscriber.changeset(attrs)
      |> Repo.insert_or_update!()

    {attrs.email, subscriber}
  end)

seed_email_memberships = [
  {"email-digest", "newsletter-reader@atlas.dev"},
  {"email-digest", "product-signup@atlas.dev"},
  {"enterprise-incident-contacts", "enterprise-ops@atlas.dev"},
  {"users", "product-signup@atlas.dev"}
]

for {audience_slug, subscriber_email} <- seed_email_memberships do
  audience = Map.fetch!(seeded_email_audiences, audience_slug)
  subscriber = Map.fetch!(seeded_email_subscribers, subscriber_email)

  membership =
    Repo.get_by(AudienceMembership, audience_id: audience.id, subscriber_id: subscriber.id) ||
      %AudienceMembership{audience_id: audience.id, subscriber_id: subscriber.id}

  membership
  |> AudienceMembership.changeset(%{status: "subscribed", unsubscribed_at: nil})
  |> Repo.insert_or_update!()
end

digest_audience = Map.fetch!(seeded_email_audiences, "email-digest")

seed_digest_broadcast =
  Repo.get_by(Broadcast, source_id: "loops-seed-tuist-digest-july-2026") ||
    %Broadcast{audience_id: digest_audience.id, sender_id: seed_user.id}

seed_digest_broadcast =
  seed_digest_broadcast
  |> Broadcast.changeset(%{
    subject: "Email Digest: July 2026",
    body_markdown: "A local example of an imported Email Digest broadcast.",
    from_name: "Pedro",
    from_email: "pedro@tuist.dev",
    reply_to_email: "pedro@tuist.dev"
  })
  |> Ecto.Changeset.change(%{
    source_id: "loops-seed-tuist-digest-july-2026",
    status: "sent",
    recipients_count: 2,
    delivered_count: 2,
    sent_at: ~U[2026-07-22 09:00:00Z]
  })
  |> Repo.insert_or_update!()

for subscriber_email <- ["newsletter-reader@atlas.dev", "product-signup@atlas.dev"] do
  subscriber = Map.fetch!(seeded_email_subscribers, subscriber_email)

  delivery =
    Repo.get_by(Delivery, broadcast_id: seed_digest_broadcast.id, recipient_email: subscriber.email) ||
      %Delivery{
        broadcast_id: seed_digest_broadcast.id,
        audience_id: digest_audience.id,
        subscriber_id: subscriber.id
      }

  delivery
  |> Delivery.changeset(%{
    kind: "broadcast",
    recipient_email: subscriber.email,
    recipient_name: Subscriber.display_name(subscriber),
    subject: seed_digest_broadcast.subject,
    status: "delivered",
    provider_message_id: "seed-#{subscriber.id}",
    delivered_at: ~U[2026-07-22 09:00:00Z]
  })
  |> Repo.insert_or_update!()
end

# Pre-populate the company Slack app's tracked channels for the demo.
demo_slack_channels = [
  %{slack_app: :company, channel_id: "C001SUPPORT", channel_name: "support"},
  %{slack_app: :company, channel_id: "C002GENERAL", channel_name: "general"},
  %{slack_app: :company, channel_id: "C003FEEDBACK", channel_name: "product-feedback"},
  %{slack_app: :company, channel_id: "C0B8KR3TRDW", channel_name: "customers"},
  %{slack_app: :company, channel_id: "C010ONCALL", channel_name: "on-call"},
  %{slack_app: :company, channel_id: "C011INCIDENTS", channel_name: "incidents"},
  %{
    slack_app: :company,
    channel_id: Application.get_env(:atlas, :briefs, [])[:leadership_slack_channel_id] || "C012LEADERSHIP",
    channel_name: "leadership"
  }
]

for channel_attrs <- demo_slack_channels do
  case Repo.get_by(SlackChannel, slack_app: channel_attrs.slack_app, channel_id: channel_attrs.channel_id) do
    nil ->
      {slack_app, attrs} = Map.pop(channel_attrs, :slack_app)

      %SlackChannel{slack_app: slack_app}
      |> SlackChannel.changeset(attrs)
      |> Repo.insert!()

    _existing ->
      :ok
  end
end

# Seed representative workspace memories so the admin memory explorer has
# useful local data before the Slack assistant saves anything.
memory_seed_time = ~U[2026-06-11 09:30:00Z]

demo_memory_nodes = [
  %{
    key: :acme_renewal_current,
    attrs: %{
      kind: :fact,
      body: "Acme renewal moved to Q4 2026 after procurement asked for the security appendix first.",
      importance: 0.85,
      slack_app: :company,
      access_count: 9,
      last_accessed_at: DateTime.add(memory_seed_time, -30, :minute)
    }
  },
  %{
    key: :acme_renewal_previous,
    attrs: %{
      kind: :fact,
      body: "Acme renewal was expected in Q3 2026 before procurement review shifted the timeline.",
      importance: 0.45,
      slack_app: :company,
      access_count: 3,
      last_accessed_at: DateTime.add(memory_seed_time, -18, :hour)
    }
  },
  %{
    key: :maya_recap_preference,
    attrs: %{
      kind: :preference,
      body: "Maya Chen prefers concise weekly renewal recaps in Slack, with procurement blockers called out first.",
      importance: 0.75,
      slack_app: :company,
      access_count: 14,
      last_accessed_at: DateTime.add(memory_seed_time, -2, :hour)
    }
  },
  %{
    key: :acme_analytics_decision,
    attrs: %{
      kind: :decision,
      body: "Atlas will keep the analytics add-on attached to the Acme renewal but bill it as a separate line item.",
      importance: 0.8,
      slack_app: :company,
      access_count: 6,
      last_accessed_at: DateTime.add(memory_seed_time, -4, :hour)
    }
  },
  %{
    key: :orbit_bank_mcp_goal,
    attrs: %{
      kind: :goal,
      body: "Follow up with Orbit Bank about exposing test insight summaries to coding agents over MCP.",
      importance: 0.65,
      slack_app: :company,
      access_count: 5,
      last_accessed_at: DateTime.add(memory_seed_time, -8, :hour)
    }
  },
  %{
    key: :orbit_bank_identity,
    attrs: %{
      kind: :identity,
      body:
        "Orbit Bank's platform team is evaluating Atlas as the internal interface for MCP-accessible engineering context.",
      importance: 0.9,
      slack_app: :company,
      access_count: 8,
      last_accessed_at: DateTime.add(memory_seed_time, -90, :minute)
    }
  },
  %{
    key: :acme_security_appendix_todo,
    attrs: %{
      kind: :todo,
      body: "Send Acme procurement the security appendix and SOC 2 bridge letter before the renewal pricing call.",
      importance: 0.88,
      slack_app: :company,
      access_count: 11,
      last_accessed_at: DateTime.add(memory_seed_time, -20, :minute)
    }
  },
  %{
    key: :procurement_appendix_fact,
    attrs: %{
      kind: :fact,
      body: "The procurement security appendix now includes data residency, model provider, and retention answers.",
      importance: 0.7,
      slack_app: :company,
      access_count: 7,
      last_accessed_at: DateTime.add(memory_seed_time, -3, :hour)
    }
  },
  %{
    key: :northstar_flaky_observation,
    attrs: %{
      kind: :observation,
      body: "Northstar Mobile asks about flaky-test triage whenever MCP or coding-agent workflows come up.",
      importance: 0.58,
      slack_app: :company,
      access_count: 4,
      last_accessed_at: DateTime.add(memory_seed_time, -11, :hour)
    }
  },
  %{
    key: :helio_cache_goal,
    attrs: %{
      kind: :goal,
      body:
        "Prepare a Helio Health cache-readiness brief that compares selective testing wins against current CI wait time.",
      importance: 0.74,
      slack_app: :company,
      access_count: 2,
      last_accessed_at: DateTime.add(memory_seed_time, -1, :day)
    }
  },
  %{
    key: :luma_release_event,
    attrs: %{
      kind: :event,
      body: "Luma Retail's release council moved the billing analytics review to June 18, 2026.",
      importance: 0.52,
      slack_app: :company,
      access_count: 4,
      last_accessed_at: DateTime.add(memory_seed_time, -6, :hour)
    }
  },
  %{
    key: :forge_finance_preference,
    attrs: %{
      kind: :preference,
      body: "Forge Finance wants renewal summaries to separate contractual blockers from product adoption blockers.",
      importance: 0.68,
      slack_app: :company,
      access_count: 3,
      last_accessed_at: DateTime.add(memory_seed_time, -2, :day)
    }
  },
  %{
    key: :maya_email_recap_preference,
    attrs: %{
      kind: :preference,
      body: "Maya Chen prefers long-form renewal recaps by email.",
      importance: 0.25,
      slack_app: :company,
      access_count: 1,
      last_accessed_at: DateTime.add(memory_seed_time, -14, :day),
      forgotten: true
    }
  },
  %{
    key: :forgotten_zoom_preference,
    attrs: %{
      kind: :preference,
      body: "Pat prefers Zoom for all customer calls.",
      importance: 0.3,
      slack_app: :company,
      access_count: 1,
      last_accessed_at: DateTime.add(memory_seed_time, -21, :day),
      forgotten: true
    }
  }
]

upsert_memory_node = fn %{attrs: attrs} ->
  desired_forgotten? = Map.get(attrs, :forgotten, false)
  {access_count, attrs} = Map.pop(attrs, :access_count)
  {last_accessed_at, attrs} = Map.pop(attrs, :last_accessed_at)
  attrs = Map.delete(attrs, :forgotten) |> Map.put_new(:scope, :global)

  node =
    case Repo.one(from node in MemoryNode, where: node.scope == :global and node.body == ^attrs.body) do
      nil ->
        {:ok, node} = Memory.create_node(attrs)
        node

      existing ->
        {:ok, node} = Memory.update_node(existing, attrs)
        node
    end

  stats_attrs =
    [access_count: access_count, last_accessed_at: last_accessed_at]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()

  node =
    if map_size(stats_attrs) > 0 do
      node
      |> Ecto.Changeset.change(stats_attrs)
      |> Repo.update!()
    else
      node
    end

  cond do
    desired_forgotten? and not node.forgotten ->
      {:ok, node} = Memory.forget_node(node)
      node

    not desired_forgotten? and node.forgotten ->
      {:ok, node} = Memory.restore_node(node)
      node

    true ->
      node
  end
end

memory_nodes_by_key =
  Map.new(demo_memory_nodes, fn seed ->
    {seed.key, upsert_memory_node.(seed)}
  end)

demo_memory_edges = [
  %{src: :acme_renewal_current, dst: :acme_renewal_previous, kind: :updates, weight: 0.95},
  %{src: :acme_renewal_current, dst: :procurement_appendix_fact, kind: :related_to, weight: 0.9},
  %{src: :acme_security_appendix_todo, dst: :acme_renewal_current, kind: :related_to, weight: 0.92},
  %{src: :maya_recap_preference, dst: :acme_renewal_current, kind: :related_to, weight: 0.72},
  %{src: :maya_recap_preference, dst: :maya_email_recap_preference, kind: :contradicts, weight: 0.9},
  %{src: :maya_recap_preference, dst: :acme_security_appendix_todo, kind: :related_to, weight: 0.65},
  %{src: :acme_analytics_decision, dst: :acme_renewal_current, kind: :related_to, weight: 0.8},
  %{src: :orbit_bank_mcp_goal, dst: :acme_analytics_decision, kind: :related_to, weight: 0.35},
  %{src: :orbit_bank_mcp_goal, dst: :orbit_bank_identity, kind: :related_to, weight: 0.86},
  %{src: :northstar_flaky_observation, dst: :orbit_bank_mcp_goal, kind: :related_to, weight: 0.48},
  %{src: :helio_cache_goal, dst: :northstar_flaky_observation, kind: :related_to, weight: 0.42},
  %{src: :luma_release_event, dst: :acme_analytics_decision, kind: :related_to, weight: 0.38},
  %{src: :forge_finance_preference, dst: :luma_release_event, kind: :related_to, weight: 0.44}
]

for edge <- demo_memory_edges do
  {:ok, _edge} =
    Memory.create_edge(%{
      src_id: Map.fetch!(memory_nodes_by_key, edge.src).id,
      dst_id: Map.fetch!(memory_nodes_by_key, edge.dst).id,
      kind: edge.kind,
      weight: edge.weight
    })
end

{:ok, _bulletin} =
  Memory.upsert_bulletin(:global, """
  Acme renewal moved to Q4 2026 because procurement needs the security appendix first. Maya wants concise weekly Slack recaps with blockers up front.

  Send Acme the updated security appendix and SOC 2 bridge letter before the pricing call. Keep the analytics add-on attached to Acme's renewal, but bill it separately.

  Follow up with Orbit Bank about MCP-accessible test insight summaries for coding agents. Northstar Mobile often connects MCP discussions to flaky-test triage, and Helio Health needs a cache-readiness brief that compares selective testing wins against current CI wait time.

  Luma Retail moved the billing analytics review to June 18, 2026. Forge Finance wants renewal summaries to split contractual blockers from product adoption blockers.
  """)

# Create GitHub apps with monitored repositories
github_apps = [
  %{
    name: "Atlas GitHub App",
    webhook_secret: "whsec_fake_dev_secret",
    app_id: "123456",
    private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake-dev-key\n-----END RSA PRIVATE KEY-----",
    installation_id: "98765",
    repositories: [
      %{owner: "tuist", repo: "tuist"},
      %{owner: "tuist", repo: "atlas"}
    ]
  }
]

for app_attrs <- github_apps do
  {repositories, app_attrs} = Map.pop(app_attrs, :repositories)

  app =
    case Repo.get_by(GitHubApp, name: app_attrs.name) do
      nil ->
        %GitHubApp{}
        |> GitHubApp.changeset(app_attrs)
        |> Repo.insert!()

      existing ->
        existing
    end

  for repo_attrs <- repositories do
    case Repo.get_by(GitHubRepository,
           owner: repo_attrs.owner,
           repo: repo_attrs.repo,
           github_app_id: app.id
         ) do
      nil ->
        %GitHubRepository{}
        |> GitHubRepository.changeset(Map.put(repo_attrs, :github_app_id, app.id))
        |> Repo.insert!()

      _existing ->
        :ok
    end
  end
end

{:ok, _gtm_signal_queries} = GTM.ensure_research_signal_queries()

stale_demo_gtm_signal_refs = [
  "seed:acme-platforms-bazel-monorepo"
]

GTMSignal
|> where([signal], signal.source == "manual" and signal.source_ref in ^stale_demo_gtm_signal_refs)
|> Repo.delete_all()

demo_gtm_outreach_signals = [
  %{
    signal: %{
      company_name: "Acme Platforms",
      company_key: "domain:acme-platforms.example",
      domain: "acme-platforms.example",
      source: "manual",
      source_ref: "seed:acme-platforms-ios-ci",
      source_url: "https://example.com/acme-platforms/ios-ci",
      title: "Acme Platforms scales iOS CI with Swift modules",
      excerpt:
        "Demo GTM signal: a mobile platform engineering team references Xcode build times, Swift module boundaries, CI throughput, and developer productivity work across a large iOS monorepo.",
      matched_terms: ["iOS", "Swift", "Xcode", "monorepo", "CI", "developer productivity"],
      signal_kind: "engineering_blog",
      confidence: 88,
      observed_at: ~U[2026-06-01 09:00:00Z],
      metadata: %{"source" => "seed", "topic" => "iOS at scale"}
    },
    contacts: [
      %{
        source: "apollo",
        full_name: "Jordan Lee",
        email: "jordan.lee@acme-platforms.example",
        title: "Director of Developer Productivity",
        organization_name: "Acme Platforms",
        linkedin_url: "https://linkedin.com/in/example-jordan-lee",
        confidence: 92,
        metadata: %{"source" => "seed", "apollo_id" => "seed-apollo-jordan-lee"}
      }
    ]
  },
  %{
    signal: %{
      company_name: "Helio Commerce",
      company_key: "domain:helio-commerce.example",
      domain: "helio-commerce.example",
      source: "manual",
      source_ref: "seed:helio-commerce-flaky-tests",
      source_url: "https://example.com/helio-commerce/flaky-tests",
      title: "Helio Commerce invests in flaky test automation",
      excerpt:
        "Demo GTM signal: engineering operations discusses flaky tests, iOS CI, build reliability, and automation conditions for a high-volume mobile test suite.",
      matched_terms: ["Flaky tests", "iOS", "CI", "build", "Automations"],
      signal_kind: "ci_scale",
      confidence: 84,
      observed_at: ~U[2026-06-02 11:00:00Z],
      metadata: %{"source" => "seed", "topic" => "Flaky tests"}
    },
    contacts: [
      %{
        source: "apollo",
        full_name: "Priya Raman",
        email: "priya.raman@helio-commerce.example",
        title: "Head of Platform Engineering",
        organization_name: "Helio Commerce",
        linkedin_url: "https://linkedin.com/in/example-priya-raman",
        confidence: 88,
        metadata: %{"source" => "seed", "apollo_id" => "seed-apollo-priya-raman"}
      }
    ]
  },
  %{
    signal: %{
      company_name: "Northstar Mobile",
      company_key: "domain:northstar-mobile.example",
      domain: "northstar-mobile.example",
      source: "manual",
      source_ref: "seed:northstar-mobile-bundle-size",
      source_url: "https://example.com/northstar-mobile/bundle-size",
      title: "Northstar Mobile tracks bundle size on pull requests",
      excerpt:
        "Demo GTM signal: mobile infrastructure work mentions pull-request bundle size thresholds, CI gates, and build feedback loops.",
      matched_terms: ["Bundle size", "Pull requests", "CI", "build"],
      signal_kind: "developer_productivity",
      confidence: 78,
      observed_at: ~U[2026-06-03 14:00:00Z],
      metadata: %{"source" => "seed", "topic" => "Bundle size"}
    },
    contacts: []
  },
  %{
    signal: %{
      company_name: "Orbit Bank",
      company_key: "domain:orbit-bank.example",
      domain: "orbit-bank.example",
      source: "manual",
      source_ref: "seed:orbit-bank-agent-test-insights",
      source_url: "https://example.com/orbit-bank/agent-test-insights",
      title: "Orbit Bank exposes test insights to coding agents",
      excerpt:
        "Demo GTM signal: developer experience work references AI agents, MCP access, test insights, and CI failure triage.",
      matched_terms: ["AI agents", "MCP", "Test insights", "CI", "developer productivity"],
      signal_kind: "developer_productivity",
      confidence: 76,
      observed_at: ~U[2026-06-04 08:00:00Z],
      metadata: %{"source" => "seed", "topic" => "AI agents"}
    },
    contacts: []
  },
  %{
    signal: %{
      company_name: "SignalWave Apps",
      company_key: "github-company:signalwave-apps",
      domain: nil,
      source: "github",
      source_ref: "seed:github:marina-ios/signalwave-ios:Project.swift",
      source_url: "https://github.com/marina-ios/signalwave-ios/blob/main/Project.swift",
      title: "marina-ios/signalwave-ios: Project.swift",
      excerpt:
        "Demo GTM signal: a public iOS repository mentions Tuist project generation, Swift modules, and Xcode project automation.",
      matched_terms: ["Tuist", "Project.swift", "Swift", "iOS", "Xcode"],
      signal_kind: "tuist_mention",
      confidence: 94,
      observed_at: ~U[2026-06-05 09:00:00Z],
      metadata: %{
        "source" => "seed",
        "topic" => "Tuist mentions",
        "mention_type" => "tuist_public_mention",
        "repository" => "marina-ios/signalwave-ios",
        "repository_url" => "https://github.com/marina-ios/signalwave-ios",
        "owner" => "marina-ios",
        "owner_type" => "User",
        "owner_company" => "SignalWave Apps",
        "person" => %{
          "login" => "marina-ios",
          "name" => "Marina Costa",
          "company" => "SignalWave Apps",
          "github_url" => "https://github.com/marina-ios",
          "blog" => "https://signalwave.example",
          "title" => "Public Tuist advocate",
          "confidence" => 86
        }
      }
    },
    contacts: []
  },
  %{
    signal: %{
      company_name: "Luma Retail",
      company_key: "github-company:luma-retail",
      domain: nil,
      source: "github",
      source_ref: "seed:github:leo-mobile/luma-store-ios:Tuist.swift",
      source_url: "https://github.com/leo-mobile/luma-store-ios/blob/main/Tuist.swift",
      title: "leo-mobile/luma-store-ios: Tuist.swift",
      excerpt:
        "Demo GTM signal: a public retail iOS workspace uses Tuist.swift and references modular Swift app targets.",
      matched_terms: ["Tuist", "Tuist.swift", "Swift", "iOS", "modules"],
      signal_kind: "tuist_mention",
      confidence: 92,
      observed_at: ~U[2026-06-05 10:00:00Z],
      metadata: %{
        "source" => "seed",
        "topic" => "Tuist advocates",
        "mention_type" => "tuist_public_mention",
        "repository" => "leo-mobile/luma-store-ios",
        "repository_url" => "https://github.com/leo-mobile/luma-store-ios",
        "owner" => "leo-mobile",
        "owner_type" => "User",
        "owner_company" => "Luma Retail",
        "person" => %{
          "login" => "leo-mobile",
          "name" => "Leo Hart",
          "company" => "Luma Retail",
          "github_url" => "https://github.com/leo-mobile",
          "blog" => "https://luma.example/engineering",
          "title" => "Public Tuist advocate",
          "confidence" => 84
        }
      }
    },
    contacts: []
  },
  %{
    signal: %{
      company_name: "Forge Finance",
      company_key: "github-company:forge-finance",
      domain: nil,
      source: "github",
      source_ref: "seed:github:sofia-builds/forge-ios:Project.swift",
      source_url: "https://github.com/sofia-builds/forge-ios/blob/main/Project.swift",
      title: "sofia-builds/forge-ios: Project.swift",
      excerpt:
        "Demo GTM signal: a public fintech iOS project mentions Tuist project generation, Xcode build graph maintenance, and CI automation.",
      matched_terms: ["Tuist", "Project.swift", "Xcode", "CI", "Swift"],
      signal_kind: "tuist_mention",
      confidence: 93,
      observed_at: ~U[2026-06-05 10:30:00Z],
      metadata: %{
        "source" => "seed",
        "topic" => "Tuist advocates",
        "mention_type" => "tuist_public_mention",
        "repository" => "sofia-builds/forge-ios",
        "repository_url" => "https://github.com/sofia-builds/forge-ios",
        "owner" => "sofia-builds",
        "owner_type" => "User",
        "owner_company" => "Forge Finance",
        "person" => %{
          "login" => "sofia-builds",
          "name" => "Sofia Nguyen",
          "company" => "Forge Finance",
          "github_url" => "https://github.com/sofia-builds",
          "blog" => "https://forge.example/mobile",
          "title" => "Public Tuist advocate",
          "confidence" => 87
        }
      }
    },
    contacts: []
  },
  %{
    signal: %{
      company_name: "Maple Health",
      company_key: "github-company:maple-health",
      domain: nil,
      source: "github",
      source_ref: "seed:github:ari-swift/maple-ios:Workspace.swift",
      source_url: "https://github.com/ari-swift/maple-ios/blob/main/Workspace.swift",
      title: "ari-swift/maple-ios: Workspace.swift",
      excerpt:
        "Demo GTM signal: a public healthcare mobile repository talks about moving an iOS workspace to Tuist for repeatable Xcode project generation.",
      matched_terms: ["Tuist", "Swift", "iOS", "Xcode"],
      signal_kind: "tuist_mention",
      confidence: 89,
      observed_at: ~U[2026-06-05 11:00:00Z],
      metadata: %{
        "source" => "seed",
        "topic" => "Tuist advocates",
        "mention_type" => "tuist_public_mention",
        "repository" => "ari-swift/maple-ios",
        "repository_url" => "https://github.com/ari-swift/maple-ios",
        "owner" => "ari-swift",
        "owner_type" => "User",
        "owner_company" => "Maple Health",
        "person" => %{
          "login" => "ari-swift",
          "name" => "Ari Patel",
          "company" => "Maple Health",
          "github_url" => "https://github.com/ari-swift",
          "blog" => "https://maple.example/tech",
          "title" => "Public Tuist advocate",
          "confidence" => 82
        }
      }
    },
    contacts: []
  }
]

for %{signal: signal_attrs, contacts: contacts} <- demo_gtm_outreach_signals do
  {:ok, signal} = GTM.record_gtm_signal(signal_attrs)
  opportunity = GTM.get_gtm_opportunity(signal.opportunity_id)

  for contact_attrs <- contacts do
    existing_contact =
      Repo.get_by(OpportunityContact,
        opportunity_id: opportunity.id,
        linkedin_url: contact_attrs.linkedin_url
      )

    (existing_contact || %OpportunityContact{opportunity_id: opportunity.id})
    |> OpportunityContact.changeset(contact_attrs)
    |> Repo.insert_or_update!()
  end
end

demo_outreach_histories = [
  %{
    source_id: "seed-apollo-jordan-lee",
    events: [
      %{kind: "connection_requested", occurred_at: ~U[2026-06-06 09:30:00Z]},
      %{kind: "connection_accepted", occurred_at: ~U[2026-06-09 15:10:00Z]},
      %{
        kind: "message_sent",
        body:
          "Hi Jordan, I enjoyed your write-up on keeping build feedback useful as the monorepo grows. What part of that work has been the hardest to make stick?",
        occurred_at: ~U[2026-06-10 08:45:00Z]
      },
      %{
        kind: "message_received",
        body:
          "Thanks! The hard part is less the tooling and more helping teams trust the feedback enough to act on it.",
        occurred_at: ~U[2026-06-10 14:20:00Z]
      }
    ]
  },
  %{
    source_id: "seed-apollo-priya-raman",
    events: [
      %{kind: "connection_requested", occurred_at: ~U[2026-06-08 10:00:00Z]}
    ]
  }
]

for %{source_id: source_id, events: events} <- demo_outreach_histories do
  suggestion =
    OpportunityContact
    |> where([contact], fragment("?->>? = ?", contact.metadata, "apollo_id", ^source_id))
    |> Repo.one!()

  {:ok, contact} = Outreach.enroll_opportunity_contact(suggestion, seed_user)

  first_activity_at = events |> hd() |> Map.fetch!(:occurred_at)

  Event
  |> where([event], event.contact_id == ^contact.id and event.kind == "enrolled")
  |> Repo.update_all(set: [occurred_at: DateTime.add(first_activity_at, -1, :hour)])

  for event_attrs <- events do
    if !Repo.exists?(
         from(event in Event,
           where: event.contact_id == ^contact.id and event.kind == ^event_attrs.kind
         )
       ) do
      {:ok, _event, _contact} = Outreach.record_event(contact, event_attrs, seed_user)
    end
  end
end

demo_outreach_recommendations = [
  %{
    source_id: "seed-apollo-jordan-lee",
    evidence_kind: "message_received",
    attrs: %{
      action_type: "reply",
      recommended_event_kind: "message_sent",
      title: "Explore how Jordan builds trust in feedback",
      guidance:
        "Reflect Jordan's point about trust, then ask how the team decides which build feedback is credible enough to act on.",
      rationale:
        "Jordan has replied with a specific organizational challenge. Staying with that concern is more useful than introducing Tuist yet.",
      draft_message:
        "That distinction makes a lot of sense. How does your team decide which build feedback engineers will trust enough to act on?",
      due_at: ~U[2026-07-20 16:00:00Z],
      confidence: Decimal.new("0.91"),
      metadata: %{
        "personalization_basis" => "Jordan's recorded reply about trust in build feedback",
        "message_strategy" => %{
          "message_intent" => "deepen_context",
          "personalization_source" => "recipient_message",
          "call_to_action" => "question"
        },
        "risks" => ["Do not turn the reply into a product pitch."]
      }
    }
  },
  %{
    source_id: "seed-apollo-priya-raman",
    evidence_kind: "connection_requested",
    attrs: %{
      action_type: "wait",
      recommended_event_kind: "note",
      title: "Give the connection request room",
      guidance:
        "Wait for Priya to accept before starting a conversation. If she does, open with one question grounded in her platform engineering work.",
      rationale:
        "The only current signal is a pending connection request. Another touch now would add pressure without adding value.",
      due_at: ~U[2026-07-24 10:00:00Z],
      confidence: Decimal.new("0.87"),
      metadata: %{
        "personalization_basis" => "The connection request recorded in Atlas",
        "risks" => ["Do not send another invitation or message while the request is pending."]
      }
    }
  }
]

for seed <- demo_outreach_recommendations do
  contact = Repo.get_by!(Contact, source: "apollo", source_id: seed.source_id)

  source_event =
    Event
    |> where([event], event.contact_id == ^contact.id and event.kind == ^seed.evidence_kind)
    |> order_by([event], desc: event.occurred_at)
    |> limit(1)
    |> Repo.one!()

  from(recommendation in Recommendation, where: recommendation.contact_id == ^contact.id)
  |> Repo.delete_all()

  %Recommendation{
    contact_id: contact.id,
    account_id: contact.account_id,
    source_event_id: source_event.id
  }
  |> Recommendation.changeset(
    seed.attrs
    |> Map.put(:status, "pending")
    |> Map.put(:generated_by_agent, "seeded_outreach_partner")
    |> Map.put(:evidence, %{
      "items" => [
        %{
          "event_id" => source_event.id,
          "observation" => source_event.body || source_event.title
        }
      ]
    })
  )
  |> Repo.insert!()

  contact
  |> Contact.outreach_recommendations_checked_changeset(%{
    outreach_recommendations_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
  })
  |> Repo.update!()
end

demo_outreach_candidates = [
  %{
    source_id: "seed-apollo-candidate-maya-chen",
    search_segment: "mobile_mid_large",
    full_name: "Maya Chen",
    email: "maya.chen@northstar-retail.example",
    title: "Director of Mobile Engineering",
    organization_name: "Northstar Retail",
    organization_source_id: "seed-apollo-org-northstar",
    organization_domain: "northstar-retail.example",
    linkedin_url: "https://linkedin.com/in/example-maya-chen",
    search_rank: 1,
    discovered_at: ~U[2026-07-20 09:00:00Z],
    metadata: %{"country" => "United States", "confidence" => 92}
  },
  %{
    source_id: "seed-apollo-candidate-lena-vogel",
    search_segment: "mobile_mid_large",
    full_name: "Lena Vogel",
    email: "lena.vogel@orbit-bank.example",
    title: "Head of iOS",
    organization_name: "Orbit Bank",
    organization_source_id: "seed-apollo-org-orbit",
    organization_domain: "orbit-bank.example",
    linkedin_url: "https://linkedin.com/in/example-lena-vogel",
    search_rank: 2,
    discovered_at: ~U[2026-07-20 09:00:00Z],
    metadata: %{"country" => "Germany", "confidence" => 95}
  },
  %{
    source_id: "seed-apollo-candidate-daniel-okafor",
    search_segment: "mobile_giants",
    full_name: "Daniel Okafor",
    email: "daniel.okafor@atlas-mobility.example",
    title: "Mobile Engineering Manager",
    organization_name: "Atlas Mobility",
    organization_source_id: "seed-apollo-org-atlas-mobility",
    organization_domain: "atlas-mobility.example",
    linkedin_url: "https://linkedin.com/in/example-daniel-okafor",
    search_rank: 1,
    discovered_at: ~U[2026-07-20 09:05:00Z],
    metadata: %{"country" => "Nigeria", "confidence" => 86}
  }
]

for attrs <- demo_outreach_candidates do
  candidate = Repo.get_by(Candidate, source: "apollo", source_id: attrs.source_id) || %Candidate{}

  candidate
  |> Candidate.changeset(
    attrs
    |> Map.put(:source, "apollo")
    |> Map.put(:search_version, 1)
    |> Map.put(:status, candidate.status || "pending")
  )
  |> Repo.insert_or_update!()
end

# Seed demo account scenarios so the CRM screens are useful locally.

demo_accounts = [
  %{
    account: %{
      account_key: "demo:acme",
      name: "Acme",
      description: "Healthy enterprise customer preparing for a renewal and an analytics add-on rollout.",
      attention_context:
        "Acme's release engineering team depends on test sharding, automations, and test selections to keep release feedback fast. Treat sustained use of those capabilities as a signal of platform dependency; connect that evidence to renewal and expansion conversations rather than treating raw usage as a success metric.",
      primary_domain: "acme.example",
      url: "https://acme.example/",
      legal_name: "Acme Inc.",
      contract_id: "Acme-2025",
      status: "active",
      segment: :customer,
      deal_stage: "negotiation",
      deal_stage_changed_at: ~U[2026-04-24 16:00:00Z],
      currency: "USD",
      current_value: 24_000,
      next_renewal_date: ~D[2026-07-15],
      stripe_customer_id: "cus_demo_acme",
      latest_activity_at: ~U[2026-05-02 14:00:00Z],
      contacts_count: 3,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "active_customer_multi_handle",
        "operate_company_domains" => ["acme.example"]
      },
      address: %{
        street: "151 O'Connor Street",
        city: "Ottawa",
        zip: "K2P 2L8",
        country: "Canada"
      },
      billing: %{
        tax_id: "EIN 12-3456789",
        sold_to: "Acme Inc.",
        bill_to: "Acme Finance",
        email: "billing@acme.example",
        phone: "+1 613 555 0142"
      },
      signatory: %{name: "Maya Chen", title: "VP Engineering"}
    },
    overview_summary: """
    **Acme** is a healthy customer heading into renewal with an analytics add-on opportunity already surfaced. The latest Granola meeting captured strong support from Maya, with procurement checklist follow-through as the main open item.

    - Confirm renewal procurement owner and timeline.
    - Keep sandbox rollout tied to the analytics expansion conversation.
    """,
    overview_summary_generated_at: ~U[2026-04-28 15:00:00Z],
    terms: [
      %{
        external_id: "demo-term:acme-2025",
        source: "enterprise",
        payment: "yearly",
        start_date: ~D[2025-07-15],
        end_date: ~D[2026-07-14],
        price_per_seat: Decimal.new("60"),
        seats: 30,
        discount: Decimal.new("0"),
        total: Decimal.new("21600"),
        currency: "USD",
        on_premise: false,
        renewal_notice_weeks: 4
      },
      %{
        external_id: "demo-term:acme-2026",
        source: "enterprise",
        payment: "yearly",
        start_date: ~D[2026-07-15],
        end_date: ~D[2027-07-14],
        price_per_seat: Decimal.new("60"),
        seats: 33,
        discount: Decimal.new("0"),
        total: Decimal.new("23760"),
        currency: "USD",
        on_premise: false,
        renewal_notice_weeks: 4,
        po_number: "PO-SHOP-2026-014"
      }
    ],
    account_handles: [
      %{handle: "acme-main", source: "enterprise"},
      %{handle: "acme-ops", source: "enterprise"},
      %{handle: "acme-sandbox", source: "enterprise"},
      %{handle: "acme", source: "tuist"}
    ],
    contacts: [
      %{
        full_name: "Maya Chen",
        email: "maya@acme.example",
        title: "VP Engineering",
        notes: "Prefers concise weekly recaps and cares deeply about rollout sequencing."
      },
      %{
        full_name: "Nico Alvarez",
        email: "nico@acme.example",
        title: "Platform PM"
      },
      %{
        full_name: "Billing Inbox",
        email: "billing@acme.example",
        title: "Billing"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:acme-pricing-comparison",
        source: "email",
        kind: "email",
        title: "Renewal pricing comparison shared with Maya",
        body: """
        Atlas CEO shared a renewal pricing comparison with Acme's Maya Chen ahead of the procurement review. Pricing proposed at **$66/seat** for 33 seats, with the analytics add-on attached as a separate line item so Finance can approve it independently.

        **From:** Test User (Atlas) **To:** Maya Chen (Acme) **Cc:** Stripe Finance

        ### Key points

        - Renewal seat count locked at **33 seats**.
        - Analytics add-on stays attached but billed as a separate line item.
        - Security appendix going out before Friday.

        ### Pricing comparison

        | Plan         | Seats | Price / seat | Annual total | Notes                                  |
        | ------------ | ----- | ------------ | ------------ | -------------------------------------- |
        | Current      | 30    | $60          | $21,600      | Expires 2026-07-14                     |
        | Renewal      | 33    | $66          | $26,136      | Locks rate for 12 months               |
        | + Analytics  | 33    | $12          | $4,752       | Separate line item, optional add-on    |

        ### Follow-up

        Awaiting confirmation from Finance on whether a fresh vendor form is needed.
        """,
        occurred_at: ~U[2026-05-28 09:30:00Z]
      },
      %{
        external_id: "demo-event:acme-term",
        source: "enterprise",
        kind: "term",
        title: "Contract term started",
        body: "#{Amounts.format(24_000, "USD")} yearly plan for the Acme production orgs.",
        occurred_at: ~U[2025-07-15 00:00:00Z],
        url: "https://dashboard.stripe.com/customers/demo_acme"
      },
      %{
        external_id: "demo-event:acme-qbr",
        source: "enterprise",
        kind: "note",
        title: "QBR identified add-on opportunity",
        body: "Customer wants deeper CI analytics for two additional product lines.",
        occurred_at: ~U[2026-04-10 13:00:00Z]
      },
      %{
        external_id: "demo-event:acme-renewal-proposal",
        source: "operate",
        kind: "deal",
        title: "Renewal proposal sent",
        body: "Ana shared the annual renewal proposal and procurement checklist.",
        occurred_at: ~U[2026-04-24 16:00:00Z]
      },
      %{
        external_id: "demo-event:acme-sandbox",
        source: "operate",
        kind: "workspace",
        title: "Sandbox rollout scheduled",
        body: "Acme requested a sandbox org for release-management experiments.",
        occurred_at: ~U[2026-04-28 14:30:00Z]
      },
      %{
        external_id: "not_demo_acme_renewal",
        source: "granola",
        kind: "meeting",
        title: "Renewal planning with Acme",
        body: """
        ## Renewal Planning

        Maya confirmed the analytics add-on is still attached to the renewal and wants the sandbox rollout to stay on the same timeline.

        ### Decisions

        - Keep the renewal at **33 seats** for the first pass.
        - Include analytics reporting in the commercial proposal.
        - Send procurement the security appendix before Friday.

        ### Follow-ups

        - Atlas: share the redlined renewal proposal.
        - Acme: confirm whether Finance needs a fresh vendor form.
        - Both teams: review sandbox rollout results in the next check-in.
        """,
        occurred_at: ~U[2026-05-02 14:00:00Z],
        url: "https://notes.granola.ai/d/demo-acme-renewal",
        metadata: %{
          "granola_note_id" => "not_demo_acme_renewal",
          "owner" => %{"name" => "Test User", "email" => "test@atlas.dev"},
          "calendar_event" => %{
            "event_title" => "Renewal planning with Acme",
            "invitees" => [
              %{"email" => "maya@acme.example"},
              %{"email" => "nico@acme.example"}
            ],
            "organiser" => "test@atlas.dev",
            "calendar_event_id" => "demo-acme-renewal-20260502T140000Z",
            "scheduled_start_time" => "2026-05-02T14:00:00Z",
            "scheduled_end_time" => "2026-05-02T14:45:00Z"
          },
          "attendees" => [
            %{"name" => "Maya Chen", "email" => "maya@acme.example"},
            %{"name" => "Nico Alvarez", "email" => "nico@acme.example"}
          ],
          "participants" => [
            %{"email" => "maya@acme.example", "name" => "Maya Chen", "roles" => ["attendee", "invitee"]},
            %{"email" => "nico@acme.example", "name" => "Nico Alvarez", "roles" => ["attendee", "invitee"]},
            %{"email" => "test@atlas.dev", "name" => "Test User", "roles" => ["owner", "organizer"]}
          ],
          "agent_participants" => [
            %{"email" => "maya@acme.example", "name" => "Maya Chen", "role" => "VP Engineering"},
            %{"email" => "nico@acme.example", "name" => "Nico Alvarez", "role" => "Platform PM"}
          ],
          "folder_membership" => [
            %{"id" => "fol_demo_customers", "object" => "folder", "name" => "Customers", "parent_folder_id" => nil}
          ],
          "summary" =>
            "Maya confirmed the analytics add-on remains part of the renewal. Procurement needs the security appendix and possibly a refreshed vendor form before the proposal can move forward.",
          "summary_text" =>
            "Maya confirmed the analytics add-on remains part of the renewal. Procurement needs the security appendix and possibly a refreshed vendor form before the proposal can move forward.",
          "summary_markdown" => """
          ## Renewal Planning

          Maya confirmed the analytics add-on is still attached to the renewal and wants the sandbox rollout to stay on the same timeline.

          ### Decisions

          - Keep the renewal at **33 seats** for the first pass.
          - Include analytics reporting in the commercial proposal.
          - Send procurement the security appendix before Friday.

          ### Follow-ups

          - Atlas: share the redlined renewal proposal.
          - Acme: confirm whether Finance needs a fresh vendor form.
          - Both teams: review sandbox rollout results in the next check-in.
          """,
          "matched_on" => %{"type" => "contact_email", "value" => "maya@acme.example"},
          "created_at" => "2026-05-02T14:48:00Z",
          "updated_at" => "2026-05-02T15:05:00Z"
        }
      }
    ]
  },
  %{
    account: %{
      account_key: "demo:acme-plus",
      name: "Acme Plus",
      description: "Business unit account nested under Acme for parent-company relationship demos.",
      primary_domain: "plus.acme.example",
      url: "https://www.acme.example/plus",
      legal_name: "Acme Plus",
      status: "active",
      segment: :customer,
      deal_stage: "closed_won",
      deal_stage_changed_at: ~U[2026-04-18 10:00:00Z],
      currency: "USD",
      current_value: 8_400,
      next_renewal_date: ~D[2026-07-15],
      latest_activity_at: ~U[2026-05-03 11:00:00Z],
      contacts_count: 1,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "child_account_parent_relationship",
        "operate_company_domains" => ["plus.acme.example"]
      }
    },
    overview_summary: """
    **Acme Plus** is modeled as a child account under Acme so the CRM can demonstrate parent-company navigation without merging business-unit records.

    - Review the parent account link on this account.
    - Review the child account link on Acme.
    """,
    overview_summary_generated_at: ~U[2026-05-03 11:05:00Z],
    terms: [],
    account_handles: [
      %{handle: "acme-plus", source: "enterprise"}
    ],
    contacts: [
      %{
        full_name: "Avery Stone",
        email: "avery@plus.acme.example",
        title: "Engineering Manager",
        notes: "Primary point of contact for the Acme Plus business unit demo account."
      }
    ],
    invoices: []
  },
  %{
    account: %{
      account_key: "demo:acme",
      name: "Acme",
      description: "Prospect in active trial with product, platform, and security stakeholders involved.",
      primary_domain: "acme.example",
      url: "https://acme.example/",
      status: "trial",
      segment: :prospect,
      deal_stage: "poc",
      deal_stage_changed_at: ~U[2026-04-29 09:00:00Z],
      poc_end_date: ~D[2026-05-15],
      currency: "USD",
      current_value: 12_500,
      latest_activity_at: ~U[2026-05-01 16:30:00Z],
      contacts_count: 2,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "prospect_trial_with_handle",
        "operate_company_domains" => ["acme.example"]
      },
      address: %{
        city: "San Francisco",
        country: "United States"
      }
    },
    overview_summary: """
    **Acme** is in technical validation with product, platform, and security stakeholders engaged. The latest meeting moved the trial toward a security review, with cache hit-rate proof points still acting as the conversion gate.

    - Send security follow-up covering SSO, caching, and data residency.
    - Prepare benchmark evidence for the large-workspace validation call.
    """,
    overview_summary_generated_at: ~U[2026-04-29 10:00:00Z],
    terms: [],
    account_handles: [
      %{handle: "acme-trial", source: "enterprise"},
      %{handle: "acme-sandbox", source: "enterprise"}
    ],
    contacts: [
      %{
        full_name: "Priya Raman",
        email: "priya@acme.example",
        title: "Staff iOS Engineer",
        notes: "Highly technical champion who responds well to concrete performance benchmarks."
      },
      %{
        full_name: "Leo Foster",
        email: "leo@acme.example",
        title: "Security Reviewer"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:acme-added",
        source: "operate",
        kind: "company",
        title: "Added to pipeline",
        body: "Inbound trial request from the mobile platform team.",
        occurred_at: ~U[2026-04-08 10:00:00Z]
      },
      %{
        external_id: "demo-event:acme-security",
        source: "enterprise",
        kind: "note",
        title: "Security questionnaire shared",
        body: "Security review covers SSO, caching, and data residency.",
        occurred_at: ~U[2026-04-18 15:30:00Z]
      },
      %{
        external_id: "demo-event:acme-trial-space",
        source: "enterprise",
        kind: "workspace",
        title: "Trial workspace provisioned",
        body: "Customer received both sandbox and trial handles for evaluation.",
        occurred_at: ~U[2026-04-24 09:00:00Z]
      },
      %{
        external_id: "demo-event:acme-validation",
        source: "operate",
        kind: "note",
        title: "Technical validation call",
        body: "Platform team wants to validate cache hit rates on a large workspace.",
        occurred_at: ~U[2026-04-29 09:00:00Z]
      },
      %{
        external_id: "not_demo_acme_security",
        source: "granola",
        kind: "meeting",
        title: "Acme trial security review",
        body: """
        ## Trial Security Review

        The platform team is happy with early setup but needs security sign-off before expanding the trial to more repositories.

        ### Signals

        - Priya called the initial cache hit rate "promising" for the mobile workspace.
        - Leo asked for details on SSO, audit logs, and data residency.
        - Acme wants a short written summary they can forward internally.

        ### Next Steps

        1. Atlas shares the security packet and cache benchmark summary.
        2. Acme confirms whether legal review is required.
        3. Schedule a final technical validation call after security review.
        """,
        occurred_at: ~U[2026-05-01 16:30:00Z],
        url: "https://notes.granola.ai/d/demo-acme-security",
        metadata: %{
          "granola_note_id" => "not_demo_acme_security",
          "owner" => %{"name" => "Test User", "email" => "test@atlas.dev"},
          "calendar_event" => %{
            "event_title" => "Acme trial security review",
            "invitees" => [
              %{"email" => "priya@acme.example"},
              %{"email" => "leo@acme.example"}
            ],
            "organiser" => "test@atlas.dev",
            "calendar_event_id" => "demo-acme-security-20260501T163000Z",
            "scheduled_start_time" => "2026-05-01T16:30:00Z",
            "scheduled_end_time" => "2026-05-01T17:15:00Z"
          },
          "attendees" => [
            %{"name" => "Priya Raman", "email" => "priya@acme.example"},
            %{"name" => "Leo Foster", "email" => "leo@acme.example"}
          ],
          "participants" => [
            %{"email" => "leo@acme.example", "name" => "Leo Foster", "roles" => ["attendee", "invitee"]},
            %{"email" => "priya@acme.example", "name" => "Priya Raman", "roles" => ["attendee", "invitee"]},
            %{"email" => "test@atlas.dev", "name" => "Test User", "roles" => ["owner", "organizer"]}
          ],
          "agent_participants" => [
            %{"email" => "priya@acme.example", "name" => "Priya Raman", "role" => "Technical champion"},
            %{"email" => "leo@acme.example", "name" => "Leo Foster", "role" => "Security reviewer"}
          ],
          "folder_membership" => [
            %{"id" => "fol_demo_trials", "object" => "folder", "name" => "Trials", "parent_folder_id" => nil}
          ],
          "summary" =>
            "Acme wants security details and cache benchmark proof points before expanding the trial. Priya remains the technical champion, while Leo owns the security review.",
          "summary_text" =>
            "Acme wants security details and cache benchmark proof points before expanding the trial. Priya remains the technical champion, while Leo owns the security review.",
          "summary_markdown" => """
          ## Trial Security Review

          The platform team is happy with early setup but needs security sign-off before expanding the trial to more repositories.

          ### Signals

          - Priya called the initial cache hit rate "promising" for the mobile workspace.
          - Leo asked for details on SSO, audit logs, and data residency.
          - Acme wants a short written summary they can forward internally.

          ### Next Steps

          1. Atlas shares the security packet and cache benchmark summary.
          2. Acme confirms whether legal review is required.
          3. Schedule a final technical validation call after security review.
          """,
          "matched_on" => %{"type" => "primary_domain", "value" => "acme.example"},
          "created_at" => "2026-05-01T17:18:00Z",
          "updated_at" => "2026-05-01T17:30:00Z"
        }
      }
    ]
  },
  %{
    account: %{
      account_key: "demo:flexport",
      name: "Flexport",
      description: "Fresh inbound lead from a CTO intro, still shaping the first discovery call.",
      primary_domain: "flexport.com",
      segment: :lead,
      deal_stage: "poc",
      deal_stage_changed_at: ~U[2026-04-27 08:30:00Z],
      poc_end_date: ~D[2026-05-08],
      latest_activity_at: ~U[2026-04-30 11:00:00Z],
      contacts_count: 1,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "lead_empty_states",
        "operate_company_domains" => ["flexport.com"]
      }
    },
    overview_summary: """
    **Flexport** is an early lead from a warm CTO intro. The account is still pre-discovery, with interest centered on monorepo performance, CI reliability, and cache hit rates.

    - Schedule the first discovery call.
    - Bring examples from similar logistics or large-monorepo teams.
    """,
    overview_summary_generated_at: ~U[2026-04-30 12:00:00Z],
    terms: [],
    account_handles: [],
    contacts: [
      %{
        full_name: "Jordan Ellis",
        email: "jordan@flexport.com",
        title: "CTO"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:flexport-intro",
        source: "operate",
        kind: "lead",
        title: "Warm intro received",
        body: "Referred by an existing customer looking for better monorepo performance.",
        occurred_at: ~U[2026-04-27 08:30:00Z]
      },
      %{
        external_id: "demo-event:flexport-discovery",
        source: "operate",
        kind: "note",
        title: "Discovery call requested",
        body: "Team wants to discuss CI reliability and cache hit rates next week.",
        occurred_at: ~U[2026-04-30 11:00:00Z]
      }
    ]
  },
  %{
    account: %{
      account_key: "demo:unity",
      name: "Unity",
      description: "Former customer that churned after consolidating developer tooling onto an internal platform.",
      primary_domain: "unity.com",
      legal_name: "Unity Software Inc.",
      contract_id: "Unity-2025",
      status: "churned",
      churned_date: ~D[2026-02-12],
      churn_reason: "Consolidated tooling onto an internal platform.",
      segment: :customer,
      currency: "EUR",
      latest_activity_at: ~U[2026-02-12 12:00:00Z],
      contacts_count: 1,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "churned_customer_history",
        "operate_company_domains" => ["unity.com"]
      },
      address: %{
        street: "Friedrichstraße 100",
        city: "Berlin",
        zip: "10117",
        country: "Germany"
      },
      billing: %{
        vat_id: "DE123456789",
        sold_to: "Unity Software Inc.",
        email: "finance@unity.com"
      },
      signatory: %{name: "Sofia Marquez", title: "Head of Mobile Platform"}
    },
    overview_summary: """
    **Unity** is churned after consolidating onto an internal build platform. The useful history is the prior expansion interest before budget and tooling strategy changed.

    - Keep the account in nurture rather than active renewal motion.
    - Re-open only if internal platform pain resurfaces.
    """,
    overview_summary_generated_at: ~U[2026-02-12 13:00:00Z],
    terms: [
      %{
        external_id: "demo-term:unity-2025",
        source: "enterprise",
        payment: "yearly",
        start_date: ~D[2025-02-01],
        end_date: ~D[2026-01-31],
        price_per_seat: Decimal.new("50"),
        seats: 30,
        total: Decimal.new("18000"),
        currency: "EUR",
        on_premise: false
      }
    ],
    account_handles: [
      %{handle: "unity-legacy", source: "enterprise"}
    ],
    contacts: [
      %{
        full_name: "Sofia Marquez",
        email: "sofia@unity.com",
        title: "Head of Mobile Platform"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:unity-contract",
        source: "enterprise",
        kind: "term",
        title: "Contract term started",
        body: "#{Amounts.format(18_000, "EUR")} annual plan for the shared mobile org.",
        occurred_at: ~U[2025-02-01 00:00:00Z]
      },
      %{
        external_id: "demo-event:unity-expansion",
        source: "operate",
        kind: "deal",
        title: "Expansion conversation opened",
        body: "Discussed adding Android and infra teams before budget changes.",
        occurred_at: ~U[2025-11-18 14:00:00Z]
      },
      %{
        external_id: "demo-event:unity-churn",
        source: "enterprise",
        kind: "note",
        title: "Churn confirmed",
        body: "Customer moved to an internal build system and declined renewal.",
        occurred_at: ~U[2026-02-12 12:00:00Z]
      }
    ]
  },
  %{
    account: %{
      account_key: "demo:wise",
      name: "Wise",
      description: "Paused customer waiting on a procurement cycle reset before reactivating usage.",
      primary_domain: "wise.com",
      legal_name: "Wise Payments Limited",
      contract_id: "Wise-2025",
      status: "paused",
      segment: :customer,
      deal_stage: "negotiation",
      deal_stage_changed_at: ~U[2026-03-21 09:00:00Z],
      currency: "USD",
      current_value: 9_000,
      next_renewal_date: ~D[2026-09-01],
      stripe_customer_id: "cus_demo_wise",
      latest_activity_at: ~U[2026-04-22 17:00:00Z],
      contacts_count: 2,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "paused_customer_reactivation",
        "operate_company_domains" => ["wise.com"]
      },
      address: %{
        street: "56 Shoreditch High Street",
        city: "London",
        zip: "E1 6JJ",
        country: "United Kingdom"
      },
      billing: %{
        tax_id: "EIN 98-7654321",
        sold_to: "Wise Payments Limited",
        bill_to: "Wise Procurement",
        email: "ap@wise.com"
      },
      signatory: %{name: "Owen Brooks", title: "Engineering Director"}
    },
    overview_summary: """
    **Wise** is paused while procurement resets the budget cycle, but the platform team is still open to a smaller restart package. The next useful motion is an ROI review tied to the two existing Tuist handles.

    - Prepare the June ROI review around risk reduction and executive visibility.
    - Keep the restart package scoped to `wise-core` and `wise-risk`.
    """,
    overview_summary_generated_at: ~U[2026-04-25 11:00:00Z],
    terms: [
      %{
        external_id: "demo-term:wise-2025",
        source: "enterprise",
        payment: "monthly",
        start_date: ~D[2025-09-01],
        end_date: ~D[2026-08-31],
        price_per_seat: Decimal.new("75"),
        seats: 10,
        discount: Decimal.new("0"),
        total: Decimal.new("9000"),
        currency: "USD",
        on_premise: false,
        renewal_notice_weeks: 6,
        po_number: "PO-WISE-2025-002"
      }
    ],
    account_handles: [
      %{handle: "wise-core", source: "enterprise"},
      %{handle: "wise-risk", source: "enterprise"}
    ],
    contacts: [
      %{
        full_name: "Owen Brooks",
        email: "owen@wise.com",
        title: "Engineering Director",
        notes: "Needs procurement updates framed around risk reduction and executive visibility."
      },
      %{
        full_name: "Casey Liu",
        email: "casey@wise.com",
        title: "Procurement"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:wise-pause",
        source: "enterprise",
        kind: "note",
        title: "Contract paused",
        body: "Procurement pushed the renewal into the next budget cycle.",
        occurred_at: ~U[2026-03-21 09:00:00Z]
      },
      %{
        external_id: "demo-event:wise-usage-checkin",
        source: "operate",
        kind: "note",
        title: "Reactivation check-in booked",
        body: "Platform team wants a fresh ROI review before June.",
        occurred_at: ~U[2026-04-22 17:00:00Z]
      },
      %{
        external_id: "demo-event:wise-renewal-plan",
        source: "enterprise",
        kind: "note",
        title: "Renewal plan drafted",
        body: "Drafted a smaller restart package tied to two Tuist handles.",
        occurred_at: ~U[2026-04-25 10:30:00Z]
      }
    ]
  },
  %{
    account: %{
      account_key: "demo:stripe",
      name: "Stripe",
      description: "Active enterprise customer with an imminent renewal and an open expansion conversation.",
      primary_domain: "stripe.com",
      url: "https://stripe.com/",
      legal_name: "Stripe, Inc.",
      contract_id: "Stripe-2025",
      status: "active",
      segment: :customer,
      deal_stage: "negotiation",
      deal_stage_changed_at: ~U[2026-05-08 09:00:00Z],
      currency: "USD",
      current_value: 36_000,
      next_renewal_date: ~D[2026-10-15],
      stripe_customer_id: "cus_demo_stripe",
      latest_activity_at: ~U[2026-05-09 18:00:00Z],
      contacts_count: 3,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "hot_renewal_in_window",
        "operate_company_domains" => ["stripe.com"]
      },
      address: %{
        street: "510 Townsend Street",
        city: "San Francisco",
        zip: "94103",
        country: "United States"
      },
      billing: %{
        tax_id: "EIN 47-3936506",
        sold_to: "Stripe, Inc.",
        bill_to: "Stripe Finance",
        email: "ap@stripe.com"
      },
      signatory: %{name: "Mira Patel", title: "Director, Developer Productivity"}
    },
    overview_summary: """
    **Stripe** is in the renewal window with the expansion conversation still attached. Mira's team is leaning toward expanding seats, but legal needs a refreshed DPA before procurement signs off.

    - Send the refreshed DPA addendum before Friday.
    - Lock the renewal seat count and the expansion line item separately.
    """,
    overview_summary_generated_at: ~U[2026-05-09 19:00:00Z],
    terms: [
      %{
        external_id: "demo-term:stripe-2025",
        source: "enterprise",
        payment: "yearly",
        start_date: ~D[2025-06-05],
        end_date: ~D[2026-06-04],
        price_per_seat: Decimal.new("90"),
        seats: 30,
        discount: Decimal.new("0"),
        total: Decimal.new("32400"),
        currency: "USD",
        on_premise: false,
        renewal_notice_weeks: 6
      }
    ],
    account_handles: [
      %{handle: "stripe-payments", source: "enterprise"},
      %{handle: "stripe-platform", source: "enterprise"}
    ],
    contacts: [
      %{
        full_name: "Mira Patel",
        email: "mira@stripe.com",
        title: "Director, Developer Productivity",
        notes: "Decision maker on the renewal. Cares about CI reliability metrics."
      },
      %{
        full_name: "Jonas Weber",
        email: "jonas@stripe.com",
        title: "Staff Engineer"
      },
      %{
        full_name: "Stripe Legal",
        email: "legal@stripe.com",
        title: "Legal"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:stripe-term",
        source: "enterprise",
        kind: "term",
        title: "Contract term started",
        body: "#{Amounts.format(32_400, "USD")} yearly plan covering the payments and platform orgs.",
        occurred_at: ~U[2025-06-05 00:00:00Z]
      },
      %{
        external_id: "demo-event:stripe-expansion",
        source: "operate",
        kind: "deal",
        title: "Expansion conversation opened",
        body: "Platform org wants their own seats and dedicated cache.",
        occurred_at: ~U[2026-05-04 14:00:00Z]
      },
      %{
        external_id: "demo-event:stripe-renewal-prep",
        source: "operate",
        kind: "note",
        title: "Renewal prep call",
        body: "Aligned on the renewal scope and next steps with Mira.",
        occurred_at: ~U[2026-05-06 15:00:00Z]
      },
      %{
        external_id: "demo-event:stripe-legal-flag",
        source: "email",
        kind: "email",
        title: "Stripe legal flagged DPA",
        body: "Legal needs a refreshed DPA before procurement starts the renewal review.",
        occurred_at: ~U[2026-05-08 09:00:00Z]
      },
      %{
        external_id: "demo-event:stripe-renewal-meeting",
        source: "granola",
        kind: "meeting",
        title: "Renewal negotiation",
        body: "Negotiated seat count and expansion line item separately.",
        occurred_at: ~U[2026-05-09 18:00:00Z]
      }
    ]
  },
  %{
    account: %{
      account_key: "demo:linear",
      name: "Linear",
      description: "Late-stage prospect in legal review with platform sign-off already in hand.",
      primary_domain: "linear.app",
      url: "https://linear.app/",
      legal_name: "Linear Orbit, Inc.",
      status: "trial",
      segment: :prospect,
      deal_stage: "legal_review",
      deal_stage_changed_at: ~U[2026-05-07 11:00:00Z],
      currency: "USD",
      current_value: 18_000,
      latest_activity_at: ~U[2026-05-09 09:30:00Z],
      contacts_count: 2,
      metadata: %{
        "matched_by" => "demo",
        "demo_scenario" => "hot_paper_process",
        "operate_company_domains" => ["linear.app"]
      },
      address: %{
        city: "Remote",
        country: "United States"
      }
    },
    overview_summary: """
    **Linear** has platform sign-off and is in legal review. The deal is ready to move once infosec returns the SOC2 evidence pack and legal closes the redlines on the MSA.

    - Send the SOC2 evidence pack to infosec today.
    - Walk through the cache enforcement profile with the platform team this week.
    """,
    overview_summary_generated_at: ~U[2026-05-09 10:00:00Z],
    terms: [],
    account_handles: [
      %{handle: "linear-trial", source: "enterprise"}
    ],
    contacts: [
      %{
        full_name: "Tomi Sato",
        email: "tomi@linear.app",
        title: "Head of Platform",
        notes: "Champion. Already aligned on rollout plan."
      },
      %{
        full_name: "Avery Lee",
        email: "legal@linear.app",
        title: "Legal Counsel"
      }
    ],
    invoices: [],
    events: [
      %{
        external_id: "demo-event:linear-trial-start",
        source: "operate",
        kind: "company",
        title: "Trial provisioned",
        body: "Linear started the trial after the platform team's evaluation request.",
        occurred_at: ~U[2026-04-22 09:00:00Z]
      },
      %{
        external_id: "demo-event:linear-platform-signoff",
        source: "operate",
        kind: "note",
        title: "Platform sign-off",
        body: "Tomi confirmed Linear is moving forward with the procurement workflow.",
        occurred_at: ~U[2026-05-05 16:00:00Z]
      },
      %{
        external_id: "demo-event:linear-legal-kickoff",
        source: "enterprise",
        kind: "note",
        title: "Legal review kicked off",
        body: "Linear's legal team started the MSA review and asked for the SOC2 pack.",
        occurred_at: ~U[2026-05-07 11:00:00Z]
      },
      %{
        external_id: "demo-event:linear-infosec-request",
        source: "email",
        kind: "email",
        title: "Infosec requested SOC2 pack",
        body: "Infosec needs the latest SOC2 evidence and the subprocessor list before they sign off.",
        occurred_at: ~U[2026-05-08 14:00:00Z]
      },
      %{
        external_id: "demo-event:linear-platform-walkthrough",
        source: "granola",
        kind: "meeting",
        title: "Platform walkthrough",
        body: "Tomi requested a walkthrough of the cache enforcement profile.",
        occurred_at: ~U[2026-05-09 09:30:00Z]
      }
    ]
  }
]

for demo <- demo_accounts do
  {deal_stage_changed_at, account_attrs} = Map.pop(demo.account, :deal_stage_changed_at)

  account =
    case Repo.get_by(Account, account_key: account_attrs.account_key) do
      nil -> %Account{}
      existing -> existing
    end
    |> Account.changeset(account_attrs)
    |> Ecto.Changeset.change(deal_stage_changed_at: deal_stage_changed_at)
    |> Repo.insert_or_update!()

  account =
    account
    |> Ecto.Changeset.change(%{
      overview_summary: demo.overview_summary,
      overview_summary_generated_at: demo.overview_summary_generated_at
    })
    |> Repo.update!()

  from(suggestion in AccountAttentionSuggestion, where: suggestion.account_id == ^account.id) |> Repo.delete_all()
  from(proposal in OutcomeProposal, where: proposal.account_id == ^account.id) |> Repo.delete_all()
  from(outcome in Outcome, where: outcome.account_id == ^account.id) |> Repo.delete_all()
  from(event in Event, where: event.account_id == ^account.id) |> Repo.delete_all()
  from(contact in Contact, where: contact.account_id == ^account.id) |> Repo.delete_all()
  from(account_handle in AccountHandle, where: account_handle.account_id == ^account.id) |> Repo.delete_all()
  from(invoice in Invoice, where: invoice.account_id == ^account.id) |> Repo.delete_all()
  from(term in Term, where: term.account_id == ^account.id) |> Repo.delete_all()

  for invoice_attrs <- demo.invoices do
    %Invoice{account_id: account.id}
    |> Invoice.changeset(invoice_attrs)
    |> Repo.insert!()
  end

  for contact_attrs <- demo.contacts do
    %Contact{}
    |> Contact.changeset(Map.put(contact_attrs, :account_id, account.id))
    |> Repo.insert!()
  end

  for account_handle_attrs <- demo.account_handles do
    %AccountHandle{}
    |> AccountHandle.changeset(Map.put(account_handle_attrs, :account_id, account.id))
    |> Repo.insert!()
  end

  for event_attrs <- Map.get(demo, :events, []) do
    event_attrs = Map.put(event_attrs, :account_id, account.id)

    %Event{}
    |> Event.changeset(event_attrs)
    |> Repo.insert!()
  end

  for term_attrs <- Map.get(demo, :terms, []) do
    %Term{account_id: account.id}
    |> Term.changeset(term_attrs)
    |> Repo.insert!()
  end
end

# Feature interest belongs to the timeline evidence, not to a single support
# channel. These meeting transcripts make the account and registry views useful
# with a fresh local database.
feature_interest_event_seeds = [
  %{
    account_key: "demo:acme",
    external_id: "seed-feature-interest:acme-remote-build-runners",
    source: "granola",
    kind: "meeting",
    title: "Release capacity planning",
    body:
      "Maya asked for predictable remote build capacity during release weeks and wants to evaluate managed remote build runners before the next peak season.",
    occurred_at: ~U[2026-06-04 10:00:00Z],
    feature_interest: %{
      title: "Remote build runners",
      summary: "Acme wants predictable remote capacity for release-week builds before its next peak season.",
      notes: "Peak-season planning is the immediate buying trigger."
    }
  },
  %{
    account_key: "demo:acme-plus",
    external_id: "seed-feature-interest:acme-plus-remote-build-runners",
    source: "granola",
    kind: "meeting",
    title: "Release validation requirements",
    body:
      "Avery needs managed remote build runners so mobile teams can scale release validation without operating another machine pool.",
    occurred_at: ~U[2026-06-05 14:30:00Z],
    feature_interest: %{
      title: "Remote build runners",
      summary: "Acme Plus wants managed runners to scale release validation without maintaining its own machines.",
      notes: "The mobile organization needs a managed option before expanding release validation."
    }
  }
]

for seed <- feature_interest_event_seeds do
  account = Repo.get_by!(Account, account_key: seed.account_key)

  event =
    Repo.get_by(Event, source: seed.source, external_id: seed.external_id) ||
      %Event{account_id: account.id}

  event =
    event
    |> Event.changeset(%{
      external_id: seed.external_id,
      source: seed.source,
      kind: seed.kind,
      title: seed.title,
      body: seed.body,
      occurred_at: seed.occurred_at,
      account_id: account.id
    })
    |> Repo.insert_or_update!()

  interest_exists? =
    Repo.exists?(
      from interest_account in FeatureInterestAccount,
        where: interest_account.account_event_id == ^event.id
    )

  if !interest_exists? do
    {:ok, _result} = Accounts.record_feature_interest_from_event(event, seed.feature_interest, seed_user)
  end
end

# Support conversations make the Support workspace useful on a fresh local
# database. These are inserted directly because they model already-delivered
# historical mail and should not enqueue outbound email jobs while seeding.
support_seed_threads = [
  %{
    customer_name: "Maya Chen",
    customer_email: "maya@acme.example",
    subject: "Cache upload stalls after a successful build",
    status: "open",
    account_key: "demo:acme",
    owner: seed_user,
    inbound_at: ~U[2026-06-03 09:15:00Z],
    inbound_body:
      "Our build finishes successfully, but the cache upload stays pending for several minutes. Can you help us understand what to check?",
    note:
      "Maya is preparing the renewal package this week. Keep the response concise and include the cache diagnostics link.",
    note_author: Repo.get_by(User, email: "alex@atlas.dev")
  },
  %{
    customer_name: "Avery Stone",
    customer_email: "avery@plus.acme.example",
    subject: "Question about selective testing coverage",
    status: "waiting",
    account_key: "demo:acme-plus",
    owner: Repo.get_by(User, email: "morgan@atlas.dev"),
    inbound_at: ~U[2026-06-02 13:30:00Z],
    inbound_body: "Does selective testing include changes to our shared test helpers?",
    reply_at: ~U[2026-06-02 14:05:00Z],
    reply_body:
      "Yes. Shared test-helper changes are part of the affected target calculation. We have also enabled the diagnostics view for your workspace."
  },
  %{
    customer_name: "Nico Alvarez",
    customer_email: "nico@acme.example",
    subject: "Access to the release dashboard",
    status: "resolved",
    account_key: "demo:acme",
    owner: seed_user,
    inbound_at: ~U[2026-05-28 16:20:00Z],
    inbound_body: "I cannot see the release dashboard for our sandbox project.",
    reply_at: ~U[2026-05-28 16:45:00Z],
    reply_body:
      "You have been added to the project role with access to releases. Please sign in again and let us know if it is still unavailable."
  },
  %{
    customer_name: "Maya Chen",
    customer_email: "maya@acme.example",
    subject: "Planning for peak release build capacity",
    status: "open",
    account_key: "demo:acme",
    owner: seed_user,
    inbound_at: ~U[2026-06-04 10:00:00Z],
    inbound_body:
      "Our release weeks need more predictable remote build capacity. We would like to evaluate managed remote build runners before the next peak season."
  },
  %{
    customer_name: "Avery Stone",
    customer_email: "avery@plus.acme.example",
    subject: "Remote build runner requirements",
    status: "waiting",
    account_key: "demo:acme-plus",
    owner: Repo.get_by(User, email: "morgan@atlas.dev"),
    inbound_at: ~U[2026-06-05 14:30:00Z],
    inbound_body:
      "Our mobile teams want managed remote build runners so they can scale release validation without maintaining another pool of machines."
  }
]

for seed <- support_seed_threads do
  account = Repo.get_by(Account, account_key: seed.account_key)

  thread =
    Repo.one(
      from thread in SupportThread,
        where: thread.customer_email == ^seed.customer_email and thread.subject == ^seed.subject
    ) ||
      %SupportThread{account_id: account && account.id, owner_id: seed.owner && seed.owner.id}

  last_message_at = Map.get(seed, :reply_at) || seed.inbound_at

  thread =
    thread
    |> SupportThread.inbound_changeset(%{
      customer_name: seed.customer_name,
      customer_email: seed.customer_email,
      subject: seed.subject,
      status: seed.status,
      last_message_at: last_message_at,
      last_inbound_at: seed.inbound_at,
      resolved_at: if(seed.status == "resolved", do: last_message_at)
    })
    |> Repo.insert_or_update!()

  inbound_message_id = "seed-support-inbound-#{thread.id}@atlas.tuist.dev"

  if !Repo.exists?(from message in SupportMessage, where: message.message_id == ^inbound_message_id) do
    %SupportMessage{
      thread_id: thread.id,
      kind: "inbound",
      message_id: inbound_message_id,
      sender_name: seed.customer_name,
      sender_email: seed.customer_email,
      to_emails: ["contact@tuist.dev"],
      body: seed.inbound_body,
      occurred_at: seed.inbound_at
    }
    |> Repo.insert!()
  end

  if seed[:reply_body] do
    reply_message_id = "seed-support-reply-#{thread.id}@atlas.tuist.dev"

    if !Repo.exists?(from message in SupportMessage, where: message.message_id == ^reply_message_id) do
      %SupportMessage{
        thread_id: thread.id,
        author_id: seed.owner && seed.owner.id,
        kind: "outbound",
        message_id: reply_message_id,
        in_reply_to: inbound_message_id,
        references: [inbound_message_id],
        sender_name: "Tuist Support",
        sender_email: "contact@tuist.dev",
        to_emails: [seed.customer_email],
        body: seed.reply_body,
        delivery_status: "delivered",
        delivered_at: seed.reply_at,
        occurred_at: seed.reply_at
      }
      |> Repo.insert!()
    end
  end

  if seed[:note] do
    note_author = seed.note_author || seed_user

    if !Repo.exists?(
         from message in SupportMessage,
           where: message.thread_id == ^thread.id and message.kind == "note" and message.body == ^seed.note
       ) do
      %SupportMessage{
        thread_id: thread.id,
        author_id: note_author.id,
        kind: "note",
        body: seed.note,
        occurred_at: DateTime.add(seed.inbound_at, 10, :minute)
      }
      |> Repo.insert!()
    end
  end
end

# Development-only customer licenses make the Licenses page useful immediately.
# The recognizable prefixes keep them from being mistaken for production credentials.
seed_licenses = [
  %{
    account_key: "demo:acme",
    key: "DEVELOPMENT-ONLY-ACME-LICENSE-7F3C-91A2",
    expires_on: ~D[2027-07-15]
  },
  %{
    account_key: "demo:wise",
    key: "DEVELOPMENT-ONLY-WISE-LICENSE-21B8-4D6E",
    expires_on: ~D[2026-12-01]
  },
  %{
    account_key: "demo:stripe",
    key: "DEVELOPMENT-ONLY-STRIPE-LICENSE-A90D-52FC",
    expires_on: ~D[2027-10-15]
  },
  %{
    account_key: "demo:unity",
    key: "DEVELOPMENT-ONLY-UNITY-LICENSE-EXPIRED",
    expires_on: ~D[2026-02-12]
  }
]

for attrs <- seed_licenses do
  account = Repo.get_by!(Account, account_key: attrs.account_key)
  key_hash = Issuer.key_hash(attrs.key)
  license = Repo.get_by(License, key_hash: key_hash) || %License{}

  license
  |> License.issued_changeset(%{
    account_id: account.id,
    key: attrs.key,
    key_hash: key_hash,
    signing_key: Base.encode64(:crypto.hash(:sha256, "development-license-signing-key:#{attrs.account_key}")),
    expires_on: attrs.expires_on
  })
  |> Repo.insert_or_update!()
end

# Seed concrete customer and prospect outcomes so the account and sales views
# show the full health spectrum with evidence-backed reviews.
outcome_seed_accounts = [
  %{
    account_key: "demo:acme",
    outcomes: [
      %{
        title: "Renew the platform agreement with procurement confidence",
        motion: "renewal",
        status: "active",
        health: "at_risk",
        description:
          "Secure the annual renewal while keeping the analytics expansion attached as a separate commercial line.",
        success_measure: "Signed annual renewal",
        baseline: "Security appendix requested",
        target: "Agreement signed for 33 seats",
        target_date: ~D[2026-08-31],
        reviewed_at: ~U[2026-07-10 09:00:00Z],
        reviews: [
          %{
            health: "at_risk",
            summary:
              "The commercial shape is agreed, but procurement cannot advance until the security appendix is accepted.",
            evidence: %{
              "items" => [
                %{
                  "source" => "customer_email",
                  "observed_at" => "2026-07-09",
                  "detail" => "Procurement confirmed that the security appendix is the remaining approval gate."
                },
                %{
                  "source" => "renewal_review",
                  "observed_at" => "2026-07-10",
                  "detail" => "Seat count and separate analytics pricing were accepted."
                }
              ]
            },
            recommendation:
              "Walk procurement through the appendix with the security owner present, then ask for a dated signature path.",
            reviewed_at: ~U[2026-07-10 09:00:00Z]
          }
        ]
      },
      %{
        title: "Prove analytics value in the sandbox team",
        motion: "expansion",
        status: "achieved",
        health: "on_track",
        description: "Validate the analytics workflow with the initial platform team before expanding it.",
        success_measure: "Weekly analytics report used in planning",
        baseline: "No shared reporting workflow",
        target: "Four consecutive weekly reports reviewed",
        target_date: ~D[2026-06-30],
        reviewed_at: ~U[2026-07-02 14:00:00Z],
        achieved_at: ~U[2026-07-02 14:00:00Z],
        closed_at: ~U[2026-07-02 14:00:00Z],
        reviews: [
          %{
            health: "on_track",
            summary:
              "The sandbox team reviewed the report for four consecutive weeks and asked to bring it into renewal planning.",
            evidence: %{
              "items" => [
                %{
                  "source" => "customer_meeting",
                  "observed_at" => "2026-07-02",
                  "detail" => "The platform lead confirmed the report is now part of weekly planning."
                }
              ]
            },
            recommendation: "Use the achieved result as evidence in the renewal and expansion conversation.",
            reviewed_at: ~U[2026-07-02 14:00:00Z]
          }
        ]
      }
    ]
  },
  %{
    account_key: "demo:acme",
    outcomes: [
      %{
        title: "Complete the enterprise security evaluation",
        motion: "evaluation",
        status: "active",
        health: "off_track",
        description: "Reach security approval with all deployment and data-handling questions resolved.",
        success_measure: "Written security approval",
        baseline: "Questionnaire open with unresolved controls",
        target: "Security approval and evaluation exit",
        target_date: ~D[2026-07-31],
        reviewed_at: ~U[2026-07-12 11:30:00Z],
        reviews: [
          %{
            health: "off_track",
            summary:
              "The technical champion remains engaged, but two data-retention controls have no accepted answer and the review date slipped.",
            evidence: %{
              "items" => [
                %{
                  "source" => "security_review",
                  "observed_at" => "2026-07-11",
                  "detail" => "The reviewer reopened the data-retention and subprocessors sections."
                },
                %{
                  "source" => "customer_slack",
                  "observed_at" => "2026-07-12",
                  "detail" => "The champion said approval cannot happen in the planned July meeting."
                }
              ]
            },
            recommendation:
              "Run a focused control review with both security teams and agree on owners and decision dates for the two open controls.",
            reviewed_at: ~U[2026-07-12 11:30:00Z]
          }
        ]
      }
    ]
  },
  %{
    account_key: "demo:stripe",
    outcomes: [
      %{
        title: "Expand weekly active developers across the mobile organization",
        motion: "adoption",
        status: "active",
        health: "on_track",
        description: "Move from the initial platform group to repeat weekly use across mobile product teams.",
        success_measure: "Weekly active developers",
        baseline: "18 weekly active developers",
        target: "45 weekly active developers",
        target_date: ~D[2026-09-15],
        reviewed_at: ~U[2026-07-13 15:00:00Z],
        reviews: [
          %{
            health: "on_track",
            summary:
              "Usage reached 31 weekly active developers after the second team rollout, with no new support blockers.",
            evidence: %{
              "items" => [
                %{
                  "source" => "product_usage",
                  "observed_at" => "2026-07-13",
                  "detail" => "Thirty-one developers were active in the trailing seven days, up from twenty-four."
                },
                %{
                  "source" => "customer_meeting",
                  "observed_at" => "2026-07-10",
                  "detail" => "The mobile infrastructure lead approved onboarding the next two teams."
                }
              ]
            },
            recommendation:
              "Keep the next two team launches on schedule and capture the first-week activation rate for each.",
            reviewed_at: ~U[2026-07-13 15:00:00Z]
          }
        ]
      }
    ]
  },
  %{
    account_key: "demo:unity",
    outcomes: [
      %{
        title: "Restore reliable use after the build stability regression",
        motion: "recovery",
        status: "active",
        health: "off_track",
        description: "Recover confidence and return the core build teams to regular use.",
        success_measure: "Successful weekly builds through Atlas",
        baseline: "Usage down 42 percent after the regression",
        target: "Usage restored to the pre-regression baseline",
        target_date: ~D[2026-08-15],
        reviewed_at: ~U[2026-07-14 08:30:00Z],
        reviews: [
          %{
            health: "off_track",
            summary: "The regression is fixed, but only one of three affected teams has resumed regular builds.",
            evidence: %{
              "items" => [
                %{
                  "source" => "product_usage",
                  "observed_at" => "2026-07-14",
                  "detail" => "Successful builds recovered for one team while two remain below ten percent of baseline."
                },
                %{
                  "source" => "support",
                  "observed_at" => "2026-07-13",
                  "detail" => "No new regression reports were received after the patch."
                }
              ]
            },
            recommendation:
              "Pair with the two inactive teams on their first successful build and monitor recovery by team, not in aggregate.",
            reviewed_at: ~U[2026-07-14 08:30:00Z]
          }
        ]
      }
    ]
  },
  %{
    account_key: "demo:linear",
    outcomes: [
      %{
        title: "Validate faster pull-request feedback in the evaluation",
        motion: "evaluation",
        status: "active",
        health: "on_track",
        description: "Demonstrate that selective testing shortens feedback without reducing confidence.",
        success_measure: "Median pull-request feedback time",
        baseline: "22 minutes",
        target: "Under 12 minutes for two consecutive weeks",
        target_date: ~D[2026-08-21],
        reviewed_at: ~U[2026-07-11 16:00:00Z],
        reviews: [
          %{
            health: "on_track",
            summary:
              "The first week reached a 13-minute median and the engineering lead approved expanding the evaluation sample.",
            evidence: %{
              "items" => [
                %{
                  "source" => "evaluation_metrics",
                  "observed_at" => "2026-07-11",
                  "detail" => "Median feedback time fell from twenty-two to thirteen minutes."
                }
              ]
            },
            recommendation: "Expand to the second repository and confirm the result holds for one more week.",
            reviewed_at: ~U[2026-07-11 16:00:00Z]
          }
        ]
      }
    ]
  }
]

for account_seed <- outcome_seed_accounts,
    %Account{} = account <- [Repo.get_by(Account, account_key: account_seed.account_key)] do
  for outcome_attrs <- account_seed.outcomes do
    {reviews, outcome_attrs} = Map.pop(outcome_attrs, :reviews, [])

    outcome =
      %Outcome{account_id: account.id, owner_id: seed_user.id}
      |> Outcome.changeset(Map.put(outcome_attrs, :metadata, %{"source" => "seed"}))
      |> Repo.insert!()

    for review_attrs <- reviews do
      %OutcomeReview{outcome_id: outcome.id, author_id: seed_user.id}
      |> OutcomeReview.changeset(Map.put(review_attrs, :metadata, %{"source" => "seed"}))
      |> Repo.insert!()
    end
  end
end

# Seed agent suggestions separately from approved outcomes. These examples let
# reviewers inspect both a proposed new outcome and a proposed review while
# preserving the evidence that led Atlas to make each suggestion.
outcome_proposal_seeds = [
  %{
    account_key: "demo:acme",
    source_event_external_id: "not_demo_acme_renewal",
    attrs: %{
      proposal_type: "new_outcome",
      title: "Expand analytics reporting into renewal planning",
      description:
        "Turn the sandbox reporting workflow into a repeatable planning input for the additional product lines.",
      motion: "expansion",
      success_measure: "Product lines using the analytics report in weekly planning",
      baseline: "One sandbox team",
      target: "Three product lines",
      target_date: ~D[2026-09-30],
      confidence: Decimal.new("0.88"),
      rationale:
        "The customer tied the analytics add-on and sandbox rollout to a concrete expansion across two more product lines.",
      observation:
        "Maya confirmed that analytics remains attached to renewal and that sandbox results will be reviewed in the next check-in."
    }
  },
  %{
    account_key: "demo:acme",
    source_event_external_id: "not_demo_acme_security",
    outcome_title: "Complete the enterprise security evaluation",
    attrs: %{
      proposal_type: "outcome_review",
      health: "at_risk",
      summary: "The technical evaluation is promising, but security approval is now the gate for expanding the trial.",
      recommendation:
        "Send the forwardable security and benchmark packet, then schedule the final validation around Leo's review date.",
      confidence: Decimal.new("0.94"),
      rationale: "The meeting introduced a material approval dependency and named the evidence needed to move forward.",
      observation:
        "Priya called the cache result promising, while Leo required SSO, audit log, and data-residency details before expansion."
    }
  }
]

for seed <- outcome_proposal_seeds,
    %Account{} = account <- [Repo.get_by(Account, account_key: seed.account_key)],
    %Event{} = source_event <-
      [Repo.get_by(Event, account_id: account.id, external_id: seed.source_event_external_id)] do
  outcome =
    case Map.get(seed, :outcome_title) do
      nil -> nil
      title -> Repo.get_by(Outcome, account_id: account.id, title: title)
    end

  attrs =
    seed.attrs
    |> Map.delete(:observation)
    |> Map.put(:status, "pending")
    |> Map.put(:generated_by_agent, "outcome_proposal_agent")
    |> Map.put(:evidence, %{
      "items" => [
        %{
          "event_id" => source_event.id,
          "observation" => seed.attrs.observation
        }
      ]
    })
    |> Map.put(
      :proposal_key,
      OutcomeProposal.proposal_key(seed.attrs.proposal_type, outcome && outcome.id, seed.attrs)
    )
    |> Map.put(:metadata, %{"source" => "seed"})

  %OutcomeProposal{
    account_id: account.id,
    outcome_id: outcome && outcome.id,
    source_event_id: source_event.id
  }
  |> OutcomeProposal.changeset(attrs)
  |> Repo.insert!()
end

demo_account_parent_links = [
  %{child_account_key: "demo:acme-plus", parent_account_key: "demo:acme"}
]

for link <- demo_account_parent_links do
  with %Account{} = child <- Repo.get_by(Account, account_key: link.child_account_key),
       %Account{} = parent <- Repo.get_by(Account, account_key: link.parent_account_key) do
    child
    |> Ecto.Changeset.change(parent_account_id: parent.id)
    |> Repo.update!()
  end
end

# Slack Connect demo: link channels to demo accounts and seed top-level
# messages with threaded replies so the Slack-aware account timeline has
# something visible out of the box.

slack_now = DateTime.utc_now() |> DateTime.truncate(:second)

slack_users_data = [
  %{
    slack_user_id: "U_PEDRO",
    name: "pedro",
    real_name: "Pedro Piñera",
    display_name: "pedro",
    avatar_url: "https://ui-avatars.com/api/?name=Pedro+Pinera&background=4f46e5&color=fff",
    is_bot: false,
    is_external: false
  },
  %{
    slack_user_id: "U_MAREK",
    name: "marek",
    real_name: "Marek Fořt",
    display_name: "marek",
    avatar_url: "https://ui-avatars.com/api/?name=Marek+Fort&background=059669&color=fff",
    is_bot: false,
    is_external: false
  },
  %{
    slack_user_id: "U_MAYA",
    name: "maya.chen",
    real_name: "Maya Chen",
    display_name: "maya.chen",
    avatar_url: "https://ui-avatars.com/api/?name=Maya+Chen&background=db2777&color=fff",
    is_bot: false,
    is_external: true
  },
  %{
    slack_user_id: "U_NICO",
    name: "nico",
    real_name: "Nico Alvarez",
    display_name: "nico",
    avatar_url: nil,
    is_bot: false,
    is_external: true
  },
  %{
    slack_user_id: "U_PRIYA",
    name: "priya.r",
    real_name: "Priya Raman",
    display_name: "priya.r",
    avatar_url: "https://ui-avatars.com/api/?name=Priya+Raman&background=f59e0b&color=fff",
    is_bot: false,
    is_external: true
  }
]

slack_users_by_id =
  for user_data <- slack_users_data, into: %{} do
    attrs = Map.put(user_data, :last_synced_at, slack_now)

    user =
      case Repo.get_by(SlackUser, slack_app: :company, slack_user_id: user_data.slack_user_id) do
        nil ->
          %SlackUser{slack_app: :company}
          |> SlackUser.changeset(attrs)
          |> Repo.insert!()

        existing ->
          existing
          |> SlackUser.changeset(attrs)
          |> Repo.update!()
      end

    {user_data.slack_user_id, user}
  end

slack_demo_scenarios = [
  %{
    account_key: "demo:northstar-retail",
    channel: %{slack_app: :company, channel_id: "C200NORTHSTAR", channel_name: "tuist-northstar"},
    threads: [
      %{
        ts: "1714400000.100100",
        author: "U_MAYA",
        text: "Hey team — could you confirm the renewal proposal for the analytics add-on lands at 33 seats?",
        posted_at: ~U[2026-04-29 14:00:00Z],
        replies: [
          %{
            ts: "1714400300.100200",
            author: "U_PEDRO",
            text: "Yes, confirmed. Sharing the redlined contract today.",
            posted_at: ~U[2026-04-29 14:05:00Z]
          },
          %{
            ts: "1714401000.100300",
            author: "U_MAYA",
            text: "Thanks! Procurement should turn it around within the week.",
            posted_at: ~U[2026-04-29 14:17:00Z]
          },
          %{
            ts: "1714402500.100400",
            author: "U_NICO",
            text: "Looping in our finance reviewer for visibility.",
            posted_at: ~U[2026-04-29 14:42:00Z]
          }
        ]
      },
      %{
        ts: "1714486400.200100",
        author: "U_PEDRO",
        text: "Latest analytics export is published — let us know if anything looks off.",
        posted_at: ~U[2026-04-30 13:00:00Z],
        replies: []
      }
    ]
  },
  %{
    account_key: "demo:bluebird-health",
    channel: %{slack_app: :company, channel_id: "C201BLUEBIRD", channel_name: "tuist-bluebird"},
    threads: [
      %{
        ts: "1714312800.300100",
        author: "U_PRIYA",
        text:
          "We finished the cache benchmark — incremental builds went from 4m12s to 1m08s. Sharing the report shortly.",
        posted_at: ~U[2026-04-28 14:00:00Z],
        replies: [
          %{
            ts: "1714313700.300200",
            author: "U_MAREK",
            text: "Beautiful! Curious if the gain holds on cold caches too.",
            posted_at: ~U[2026-04-28 14:15:00Z]
          },
          %{
            ts: "1714314600.300300",
            author: "U_PRIYA",
            text: "Cold cache hit ratio is 91% in our trial workspace.",
            posted_at: ~U[2026-04-28 14:30:00Z]
          }
        ]
      }
    ]
  }
]

for scenario <- slack_demo_scenarios do
  case Repo.get_by(Account, account_key: scenario.account_key) do
    nil ->
      :ok

    account ->
      channel =
        case Repo.get_by(SlackChannel,
               slack_app: scenario.channel.slack_app,
               channel_id: scenario.channel.channel_id
             ) do
          nil ->
            {slack_app, attrs} = Map.pop(scenario.channel, :slack_app)

            %SlackChannel{account_id: account.id, slack_app: slack_app}
            |> SlackChannel.changeset(attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> SlackChannel.account_changeset(account.id)
            |> Repo.update!()
        end

      from(m in SlackMessage, where: m.slack_channel_id == ^channel.id) |> Repo.delete_all()

      from(e in Event, where: e.account_id == ^account.id and e.kind == "slack_message")
      |> Repo.delete_all()

      for thread <- scenario.threads do
        author = Map.fetch!(slack_users_by_id, thread.author)

        permalink =
          "https://tuist.slack.com/archives/#{scenario.channel.channel_id}/p#{String.replace(thread.ts, ".", "")}"

        event =
          %Event{}
          |> Event.changeset(%{
            "external_id" => "slack:#{scenario.channel.slack_app}:#{scenario.channel.channel_id}:#{thread.ts}",
            "source" => "slack",
            "kind" => "slack_message",
            "title" => String.slice(thread.text, 0, 120),
            "body" => thread.text,
            "occurred_at" => thread.posted_at,
            "url" => permalink,
            "account_id" => account.id,
            "metadata" => %{
              "slack_app" => Atom.to_string(scenario.channel.slack_app),
              "channel_id" => scenario.channel.channel_id,
              "channel_name" => scenario.channel.channel_name,
              "slack_ts" => thread.ts,
              "author_slack_user_id" => author.slack_user_id,
              "author_name" => SlackUser.best_display_name(author),
              "author_avatar_url" => author.avatar_url,
              "author_is_external" => author.is_external,
              "author_is_bot" => author.is_bot
            }
          })
          |> Repo.insert!()

        %SlackMessage{
          slack_channel_id: channel.id,
          slack_user_id: author.id,
          account_event_id: event.id
        }
        |> SlackMessage.changeset(%{
          slack_ts: thread.ts,
          thread_ts: nil,
          text: thread.text,
          permalink: permalink,
          posted_at: thread.posted_at
        })
        |> Repo.insert!()

        for reply <- thread.replies do
          reply_author = Map.fetch!(slack_users_by_id, reply.author)

          reply_permalink =
            "https://tuist.slack.com/archives/#{scenario.channel.channel_id}/p#{String.replace(reply.ts, ".", "")}"

          %SlackMessage{
            slack_channel_id: channel.id,
            slack_user_id: reply_author.id
          }
          |> SlackMessage.changeset(%{
            slack_ts: reply.ts,
            thread_ts: thread.ts,
            text: reply.text,
            permalink: reply_permalink,
            posted_at: reply.posted_at
          })
          |> Repo.insert!()
        end
      end
  end
end

# Agent session audit: a few representative `Atlas.Agents.Sessions` rows so
# the audit page has something visible in dev without needing to actually
# invoke an LLM. Each scenario is keyed by its agent module name and skipped
# individually when a row for that agent already exists, so re-running
# seeds.exs adds any newly introduced demo session without touching existing
# rows.
acme = Repo.get_by(Account, account_key: "demo:acme")
acme = Repo.get_by(Account, account_key: "demo:acme")

insert_agent_session = fn attrs, events ->
  started_at = attrs.started_at
  finished_at = attrs[:finished_at] || DateTime.add(started_at, attrs[:duration_ms] || 0, :millisecond)

  session_attrs =
    attrs
    |> Map.take([:id, :agent, :prompt, :account_id])
    |> Map.merge(%{status: "running", started_at: started_at})

  session_attrs
  |> AgentSession.create_changeset()
  |> Repo.insert!()

  AgentSession
  |> Repo.get!(attrs.id)
  |> AgentSession.finalize_changeset(%{
    status: attrs.status,
    finished_at: finished_at,
    duration_ms: attrs[:duration_ms],
    result: attrs[:result],
    error: attrs[:error]
  })
  |> Repo.update!()

  for {event_attrs, offset_ms} <- Enum.with_index(events, 1) do
    occurred_at = DateTime.add(started_at, offset_ms * 100, :millisecond)

    event_attrs
    |> Map.put(:agent_session_id, attrs.id)
    |> Map.put(:occurred_at, occurred_at)
    |> AgentSessionEvent.changeset()
    |> Repo.insert!()
  end
end

agent_session_seeded? = fn agent_name ->
  Repo.exists?(from s in AgentSession, where: s.agent == ^agent_name)
end

if acme && !agent_session_seeded?.("Atlas.Accounts.Agents.EmailEventAgent") do
  insert_agent_session.(
    %{
      id: Atlas.UUIDv7.generate(),
      agent: "Atlas.Accounts.Agents.EmailEventAgent",
      prompt: "Process this inbound email about Acme renewal terms.",
      account_id: acme.id,
      status: "succeeded",
      started_at: DateTime.add(DateTime.utc_now(), -3600, :second),
      duration_ms: 4_320,
      result: %{
        "status" => "captured",
        "event_id" => "demo-event-1",
        "account_id" => acme.id
      }
    },
    [
      %{type: "run", phase: "start", metadata: %{"structured?" => true, "input?" => false}},
      %{type: "agent", phase: "start", metadata: %{"agent" => "Condukt.AnonymousAgent"}},
      %{
        type: "llm_turn",
        name: "turn 0",
        phase: "start",
        metadata: %{
          "turn" => 0,
          "agent" => "Condukt.AnonymousAgent",
          "model" => "anthropic:claude-sonnet-4-6",
          "tool_count" => 4,
          "messages" => [
            %{"role" => "user", "content" => "Process this inbound email about Acme renewal terms."}
          ]
        }
      },
      %{
        type: "llm_turn",
        name: "turn 0",
        phase: "stop",
        duration_ms: 1_240,
        metadata: %{
          "turn" => 0,
          "agent" => "Condukt.AnonymousAgent",
          "model" => "anthropic:claude-sonnet-4-6",
          "tool_count" => 4,
          "status" => "ok",
          "finish_reason" => "tool_calls",
          "usage" => %{"input_tokens" => 312, "output_tokens" => 84},
          "assistant_message" => %{
            "role" => "assistant",
            "content" => [
              %{"type" => "text", "text" => "Looking up the account for the email participants."}
            ]
          }
        }
      },
      %{
        type: "tool_call",
        name: "find_account",
        phase: "start",
        metadata: %{
          "tool" => "find_account",
          "tool_call_id" => "call_find_1",
          "args" => %{"emails" => ["pedro@acme.example", "sales@atlas.tuist.dev"]}
        }
      },
      %{
        type: "tool_call",
        name: "find_account",
        phase: "stop",
        duration_ms: 90,
        metadata: %{
          "tool" => "find_account",
          "tool_call_id" => "call_find_1",
          "status" => "ok",
          "result" => %{
            "found" => true,
            "account" => %{"id" => acme.id, "name" => acme.name}
          }
        }
      },
      %{
        type: "tool_call",
        name: "store_email_event",
        phase: "start",
        metadata: %{
          "tool" => "store_email_event",
          "tool_call_id" => "call_store_1",
          "args" => %{"account_id" => acme.id, "title" => "Renewal terms discussion"}
        }
      },
      %{
        type: "tool_call",
        name: "store_email_event",
        phase: "stop",
        duration_ms: 140,
        metadata: %{
          "tool" => "store_email_event",
          "tool_call_id" => "call_store_1",
          "status" => "ok",
          "result" => %{"event_id" => "demo-event-1"}
        }
      },
      %{
        type: "llm_turn",
        name: "turn 1",
        phase: "start",
        metadata: %{
          "turn" => 1,
          "agent" => "Condukt.AnonymousAgent",
          "model" => "anthropic:claude-sonnet-4-6",
          "tool_count" => 4
        }
      },
      %{
        type: "llm_turn",
        name: "turn 1",
        phase: "stop",
        duration_ms: 760,
        metadata: %{
          "turn" => 1,
          "agent" => "Condukt.AnonymousAgent",
          "model" => "anthropic:claude-sonnet-4-6",
          "tool_count" => 4,
          "status" => "ok",
          "finish_reason" => "stop",
          "usage" => %{"input_tokens" => 612, "output_tokens" => 96},
          "assistant_message" => %{
            "role" => "assistant",
            "content" => [
              %{"type" => "text", "text" => "Captured the renewal terms email as a Acme timeline event."}
            ]
          }
        }
      },
      %{type: "agent", phase: "stop", duration_ms: 4_200, metadata: %{"agent" => "Condukt.AnonymousAgent"}},
      %{type: "run", phase: "stop", duration_ms: 4_320, metadata: %{"structured?" => true, "input?" => false}}
    ]
  )
end

if acme && !agent_session_seeded?.("Atlas.Accounts.Agents.OverviewSummaryAgent") do
  insert_agent_session.(
    %{
      id: Atlas.UUIDv7.generate(),
      agent: "Atlas.Accounts.Agents.OverviewSummaryAgent",
      prompt: "Draft the current overview summary for this account.\n\nAccount: Acme",
      account_id: acme.id,
      status: "failed",
      started_at: DateTime.add(DateTime.utc_now(), -1800, :second),
      duration_ms: 980,
      error: "{:llm_provider_error, :rate_limited}"
    },
    [
      %{
        type: "operation",
        name: "summarize",
        phase: "start",
        metadata: %{"agent" => "Atlas.Accounts.Agents.OverviewSummaryAgent", "operation" => "summarize"}
      },
      %{type: "run", phase: "start", metadata: %{"structured?" => false, "input?" => false}},
      %{type: "agent", phase: "start", metadata: %{"agent" => "Atlas.Accounts.Agents.OverviewSummaryAgent"}},
      %{
        type: "agent",
        phase: "exception",
        duration_ms: 920,
        metadata: %{
          "agent" => "Atlas.Accounts.Agents.OverviewSummaryAgent",
          "kind" => "error",
          "reason" => "{:llm_provider_error, :rate_limited}"
        }
      }
    ]
  )
end

# Seed a wider renewal base so the Finance page's Coverage and
# Committed-pipeline widgets demo as something close to profitability
# rather than a single-digit coverage ratio. These are lightweight
# accounts (no contacts, events, or documents) chosen to span EUR/USD/
# GBP currencies and the rest of the calendar year for renewals.
renewal_demo_accounts = [
  %{
    account_key: "demo:renewal-monday",
    name: "Monday",
    primary_domain: "monday.com",
    currency: "EUR",
    current_value: 6_720,
    next_renewal_date: ~D[2026-07-22]
  },
  %{
    account_key: "demo:renewal-loom",
    name: "Loom",
    primary_domain: "loom.com",
    currency: "USD",
    current_value: 42_000,
    next_renewal_date: ~D[2026-08-14]
  },
  %{
    account_key: "demo:renewal-figma",
    name: "Figma",
    primary_domain: "figma.com",
    currency: "USD",
    current_value: 54_000,
    next_renewal_date: ~D[2026-09-05]
  },
  %{
    account_key: "demo:renewal-posthog",
    name: "PostHog",
    primary_domain: "posthog.com",
    currency: "USD",
    current_value: 28_000,
    next_renewal_date: ~D[2026-09-28]
  },
  %{
    account_key: "demo:renewal-openai",
    name: "OpenAI",
    primary_domain: "openai.com",
    currency: "USD",
    current_value: 36_000,
    next_renewal_date: ~D[2026-10-01]
  },
  %{
    account_key: "demo:renewal-datadog",
    name: "Datadog",
    primary_domain: "datadoghq.com",
    currency: "USD",
    current_value: 72_000,
    next_renewal_date: ~D[2026-10-20]
  },
  %{
    account_key: "demo:renewal-qonto",
    name: "Qonto",
    primary_domain: "qonto.com",
    currency: "EUR",
    current_value: 32_400,
    next_renewal_date: ~D[2026-11-10]
  },
  %{
    account_key: "demo:renewal-acme",
    name: "Acme",
    primary_domain: "acme.example",
    currency: "GBP",
    current_value: 48_000,
    next_renewal_date: ~D[2026-11-26]
  },
  %{
    account_key: "demo:renewal-sentry",
    name: "Sentry",
    primary_domain: "sentry.io",
    currency: "USD",
    current_value: 24_000,
    next_renewal_date: ~D[2026-12-10]
  },
  %{
    account_key: "demo:renewal-gitlab",
    name: "GitLab",
    primary_domain: "gitlab.com",
    currency: "USD",
    current_value: 60_000,
    next_renewal_date: ~D[2027-02-04]
  }
]

for attrs <- renewal_demo_accounts do
  account_attrs =
    attrs
    |> Map.put(:status, "active")
    |> Map.put(:segment, :customer)
    |> Map.put(:deal_stage, "closed_won")
    |> Map.put_new(:metadata, %{"matched_by" => "demo", "demo_scenario" => "renewal_base"})

  case Repo.get_by(Account, account_key: attrs.account_key) do
    nil -> %Account{}
    existing -> existing
  end
  |> Account.changeset(account_attrs)
  |> Repo.insert_or_update!()
end

# Seed normalized finance data so the Finance page and finance MCP
# tools have useful local records before live credentials are wired in.
finance_now = ~U[2026-05-26 09:30:00Z]

upsert_internal_account = fn attrs ->
  attrs =
    Map.merge(
      %{
        segment: :customer,
        status: "active",
        metadata: %{"internal_company" => true}
      },
      attrs
    )

  case Repo.get_by(Account, account_key: attrs.account_key) do
    nil -> %Account{}
    existing -> existing
  end
  |> Account.changeset(attrs)
  |> Repo.insert_or_update!()
end

upsert_finance_source = fn attrs ->
  case Repo.get_by(FinanceSource, config_key: attrs.config_key) do
    nil -> %FinanceSource{}
    existing -> existing
  end
  |> FinanceSource.changeset(attrs)
  |> Repo.insert_or_update!()
end

upsert_finance_account = fn source, attrs ->
  attrs = Map.put(attrs, :finance_source_id, source.id)

  case Repo.get_by(FinanceAccount, finance_source_id: source.id, external_id: attrs.external_id) do
    nil -> %FinanceAccount{}
    existing -> existing
  end
  |> FinanceAccount.changeset(attrs)
  |> Repo.insert_or_update!()
end

upsert_finance_category = fn attrs ->
  case Repo.get_by(FinanceCategory, slug: FinanceCategory.slugify(attrs.name)) do
    nil -> %FinanceCategory{}
    existing -> existing
  end
  |> FinanceCategory.changeset(attrs)
  |> Repo.insert_or_update!()
end

upsert_finance_transaction = fn account, attrs ->
  attrs =
    attrs
    |> Map.put(:finance_account_id, account.id)
    |> Map.put_new(:provider, account.provider)

  case Repo.get_by(FinanceTransaction,
         finance_account_id: account.id,
         external_id: attrs.external_id
       ) do
    nil -> %FinanceTransaction{}
    existing -> existing
  end
  |> FinanceTransaction.changeset(attrs)
  |> Repo.insert_or_update!()
end

finance_categories =
  [
    payroll: %{
      name: "Payroll",
      description: "Employee payroll and employer payroll provider payments.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    revenue: %{
      name: "Revenue",
      description: "Customer invoice payments, contract wires, and other operating revenue.",
      direction: "credit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    cloud_infrastructure: %{
      name: "Cloud Infrastructure",
      description: "Cloud hosting, compute, storage, observability, and infrastructure platforms.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    rent: %{
      name: "Rent",
      description: "Office rent, leases, and workspace commitments.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    taxes: %{
      name: "Taxes",
      description: "Tax payments, social contributions, and statutory filings.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    contractors: %{
      name: "Contractors",
      description: "Contractor and freelancer payments.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    software: %{
      name: "Software",
      description: "Recurring SaaS tools, developer tools, and AI platform spend.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    },
    banking_fees: %{
      name: "Banking Fees",
      description: "Bank transfer, card, account, and wire fees.",
      direction: "debit",
      created_by_agent: "seed",
      metadata: %{"seed" => true}
    }
  ]
  |> Map.new(fn {key, attrs} -> {key, upsert_finance_category.(attrs)} end)

tuist_gmbh_account =
  upsert_internal_account.(%{
    account_key: "operate:tuist-gmbh",
    name: "Tuist GmbH",
    legal_name: "Tuist GmbH",
    description: "Internal operating entity for EMEA banking and treasury.",
    currency: "EUR"
  })

tuist_inc_account =
  upsert_internal_account.(%{
    account_key: "operate:tuist-inc",
    name: "Tuist Inc.",
    legal_name: "Tuist Inc.",
    description: "Internal operating entity for US banking and treasury.",
    currency: "USD"
  })

qonto_source =
  upsert_finance_source.(%{
    atlas_account_id: tuist_gmbh_account.id,
    provider: "qonto",
    config_key: "seed-qonto-main",
    name: "Qonto Main",
    external_id: "organization_seed_qonto",
    last_synced_at: finance_now,
    last_successful_sync_at: finance_now,
    metadata: %{"seed" => true, "environment" => "development", "atlas_account" => "Tuist GmbH"}
  })

mercury_source =
  upsert_finance_source.(%{
    atlas_account_id: tuist_inc_account.id,
    provider: "mercury",
    config_key: "seed-mercury-main",
    name: "Mercury Main",
    external_id: "organization_seed_mercury",
    last_synced_at: finance_now,
    last_successful_sync_at: DateTime.add(finance_now, -2 * 60, :second),
    metadata: %{"seed" => true, "environment" => "development", "atlas_account" => "Tuist Inc."}
  })

qonto_operating =
  upsert_finance_account.(qonto_source, %{
    provider: "qonto",
    external_id: "qonto_operating",
    name: "Operating",
    account_type: "checking",
    currency: "EUR",
    main: true,
    status: "active",
    balance_value: Decimal.new("70000.00"),
    balance_currency: "EUR",
    available_balance_value: Decimal.new("65000.00"),
    available_balance_currency: "EUR",
    transactions_synced_at: finance_now,
    refreshed_at: finance_now,
    metadata: %{"seed" => true}
  })

qonto_payroll =
  upsert_finance_account.(qonto_source, %{
    provider: "qonto",
    external_id: "qonto_payroll",
    name: "Payroll",
    account_type: "checking",
    currency: "EUR",
    main: false,
    status: "active",
    balance_value: Decimal.new("17000.00"),
    balance_currency: "EUR",
    available_balance_value: Decimal.new("15000.00"),
    available_balance_currency: "EUR",
    transactions_synced_at: finance_now,
    refreshed_at: finance_now,
    metadata: %{"seed" => true}
  })

mercury_operating =
  upsert_finance_account.(mercury_source, %{
    provider: "mercury",
    external_id: "mercury_operating",
    name: "US Operating",
    account_type: "checking",
    currency: "USD",
    main: true,
    status: "active",
    balance_value: Decimal.new("132000.00"),
    balance_currency: "USD",
    available_balance_value: Decimal.new("128500.00"),
    available_balance_currency: "USD",
    transactions_synced_at: finance_now,
    refreshed_at: finance_now,
    metadata: %{"seed" => true}
  })

finance_transactions = [
  # Partial-month June 2026 activity so the calendar-month income/expenses
  # chart and the "Income this month" widget have data for the current
  # month when seeds are run in mid-June.
  {qonto_operating,
   %{
     external_id: "seed_qonto_invoice_payment_june",
     status: "completed",
     direction: "credit",
     kind: "invoice_payment",
     counterparty_name: "Northstar GmbH",
     description: "Invoice 2026-062",
     reference: "INV-2026-062",
     amount_value: Decimal.new("18000.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.revenue.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9800"),
     categorization_reason: "Customer invoice payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-06-04 08:30:00Z],
     settled_at: ~U[2026-06-04 08:30:00Z],
     provider_updated_at: ~U[2026-06-04 08:30:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_infra_june",
     status: "completed",
     direction: "debit",
     kind: "subscription",
     counterparty_name: "Amazon Web Services",
     description: "Infrastructure bill",
     reference: "AWS-2026-06",
     amount_value: Decimal.new("6700.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.cloud_infrastructure.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9600"),
     categorization_reason: "Cloud infrastructure bill",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-06-16 10:15:00Z],
     settled_at: ~U[2026-06-16 10:15:00Z],
     provider_updated_at: ~U[2026-06-16 10:15:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_rent_june",
     status: "completed",
     direction: "debit",
     kind: "rent",
     counterparty_name: "Berlin Office Lease",
     description: "HQ rent",
     reference: "RENT-JUN",
     amount_value: Decimal.new("4200.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.rent.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9700"),
     categorization_reason: "Office lease payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-06-10 07:45:00Z],
     settled_at: ~U[2026-06-10 07:45:00Z],
     provider_updated_at: ~U[2026-06-10 07:45:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {mercury_operating,
   %{
     external_id: "seed_mercury_customer_wire_june",
     status: "sent",
     direction: "credit",
     kind: "incoming_domestic_wire",
     counterparty_name: "Acme Inc.",
     description: "Quarterly enterprise installment",
     reference: "WIRE-ACME-2026-06",
     amount_value: Decimal.new("12500.00"),
     amount_currency: "USD",
     finance_category_id: finance_categories.revenue.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9800"),
     categorization_reason: "Enterprise contract installment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-06-09 15:00:00Z],
     settled_at: ~U[2026-06-09 15:00:00Z],
     provider_updated_at: ~U[2026-06-09 15:00:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "mercury"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_invoice_payment",
     status: "completed",
     direction: "credit",
     kind: "invoice_payment",
     counterparty_name: "Northstar GmbH",
     description: "Invoice 2026-051",
     reference: "INV-2026-051",
     amount_value: Decimal.new("18000.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.revenue.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9800"),
     categorization_reason: "Customer invoice payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-23 08:30:00Z],
     settled_at: ~U[2026-05-23 08:30:00Z],
     provider_updated_at: ~U[2026-05-23 08:30:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_payroll,
   %{
     external_id: "seed_qonto_payroll",
     status: "completed",
     direction: "debit",
     kind: "salary",
     counterparty_name: "Deel",
     description: "May payroll run",
     reference: "PAYROLL-MAY",
     amount_value: Decimal.new("26000.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.payroll.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9900"),
     categorization_reason: "Payroll provider payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-22 09:00:00Z],
     settled_at: ~U[2026-05-22 09:00:00Z],
     provider_updated_at: ~U[2026-05-22 09:00:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_infra",
     status: "completed",
     direction: "debit",
     kind: "subscription",
     counterparty_name: "Amazon Web Services",
     description: "Infrastructure bill",
     reference: "AWS-2026-05",
     amount_value: Decimal.new("6500.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.cloud_infrastructure.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9600"),
     categorization_reason: "Cloud infrastructure bill",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-16 10:15:00Z],
     settled_at: ~U[2026-05-16 10:15:00Z],
     provider_updated_at: ~U[2026-05-16 10:15:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_rent",
     status: "completed",
     direction: "debit",
     kind: "rent",
     counterparty_name: "Berlin Office Lease",
     description: "HQ rent",
     reference: "RENT-MAY",
     amount_value: Decimal.new("4200.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.rent.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9700"),
     categorization_reason: "Office lease payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-10 07:45:00Z],
     settled_at: ~U[2026-05-10 07:45:00Z],
     provider_updated_at: ~U[2026-05-10 07:45:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_tax",
     status: "completed",
     direction: "debit",
     kind: "tax",
     counterparty_name: "URSSAF",
     description: "Social contributions",
     reference: "TAX-Q2",
     amount_value: Decimal.new("14500.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.taxes.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9500"),
     categorization_reason: "Social contributions tax payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-03 11:20:00Z],
     settled_at: ~U[2026-05-03 11:20:00Z],
     provider_updated_at: ~U[2026-05-03 11:20:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_contractors",
     status: "completed",
     direction: "debit",
     kind: "contractor_payment",
     counterparty_name: "Contractor Batch",
     description: "April contractors",
     reference: "CTR-APR",
     amount_value: Decimal.new("12800.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.contractors.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9300"),
     categorization_reason: "Contractor batch payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-04-22 13:40:00Z],
     settled_at: ~U[2026-04-22 13:40:00Z],
     provider_updated_at: ~U[2026-04-22 13:40:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {qonto_operating,
   %{
     external_id: "seed_qonto_support_tools",
     status: "completed",
     direction: "debit",
     kind: "subscription",
     counterparty_name: "Linear",
     description: "Engineering tooling",
     reference: "LINEAR-MAY",
     amount_value: Decimal.new("980.00"),
     amount_currency: "EUR",
     finance_category_id: finance_categories.software.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9200"),
     categorization_reason: "Engineering SaaS subscription",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-04-08 15:10:00Z],
     settled_at: ~U[2026-04-08 15:10:00Z],
     provider_updated_at: ~U[2026-04-08 15:10:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "qonto"}
   }},
  {mercury_operating,
   %{
     external_id: "seed_mercury_annual_contract",
     status: "sent",
     direction: "credit",
     kind: "incoming_domestic_wire",
     counterparty_name: "Acme Inc.",
     description: "Annual enterprise contract",
     reference: "WIRE-ACME-2026",
     amount_value: Decimal.new("36000.00"),
     amount_currency: "USD",
     finance_category_id: finance_categories.revenue.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9800"),
     categorization_reason: "Annual enterprise contract wire",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-21 16:15:00Z],
     settled_at: ~U[2026-05-21 16:15:00Z],
     provider_updated_at: ~U[2026-05-21 16:15:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "mercury"}
   }},
  {mercury_operating,
   %{
     external_id: "seed_mercury_payroll",
     status: "sent",
     direction: "debit",
     kind: "outgoing_payment",
     counterparty_name: "Rippling",
     description: "US payroll",
     reference: "PAYROLL-US-MAY",
     amount_value: Decimal.new("18500.00"),
     amount_currency: "USD",
     finance_category_id: finance_categories.payroll.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9900"),
     categorization_reason: "US payroll provider payment",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-05-18 14:40:00Z],
     settled_at: ~U[2026-05-18 14:40:00Z],
     provider_updated_at: ~U[2026-05-18 14:40:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "mercury"}
   }},
  {mercury_operating,
   %{
     external_id: "seed_mercury_software",
     status: "sent",
     direction: "debit",
     kind: "debit_card_transaction",
     counterparty_name: "OpenAI",
     description: "AI platform spend",
     reference: "OPENAI-MAY",
     amount_value: Decimal.new("2400.00"),
     amount_currency: "USD",
     finance_category_id: finance_categories.software.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9000"),
     categorization_reason: "AI platform software spend",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-04-29 11:25:00Z],
     settled_at: ~U[2026-04-29 11:25:00Z],
     provider_updated_at: ~U[2026-04-29 11:25:00Z],
     metadata: %{"seed" => true},
     raw: %{"provider" => "mercury"}
   }},
  {mercury_operating,
   %{
     external_id: "seed_mercury_fee",
     status: "sent",
     direction: "debit",
     kind: "wire_fee",
     counterparty_name: "Mercury",
     description: "Wire fee",
     reference: "WIRE-FEE-APR",
     amount_value: Decimal.new("15.00"),
     amount_currency: "USD",
     finance_category_id: finance_categories.banking_fees.id,
     categorized_at: finance_now,
     categorization_confidence: Decimal.new("0.9900"),
     categorization_reason: "Bank wire fee",
     categorized_by_agent: "seed",
     booked_at: ~U[2026-04-12 09:10:00Z],
     settled_at: ~U[2026-04-12 09:10:00Z],
     provider_updated_at: ~U[2026-04-12 09:10:00Z],
     affects_runway: false,
     metadata: %{"seed" => true},
     raw: %{"provider" => "mercury"}
   }}
]

# Generate ~24 months of recurring activity so runway charts have
# enough history to visualise burn rate, bank balance, and runway
# evolution across the last two years.
historical_months = 1..23

month_offset_at = fn months_ago ->
  base = Date.from_iso8601!("2026-05-01")
  total_months = base.year * 12 + (base.month - 1) - months_ago
  year = div(total_months, 12)
  month = rem(total_months, 12) + 1
  {year, month}
end

# Linear scale that makes the company look smaller two years ago.
scale_for = fn months_ago ->
  Decimal.from_float(1.0 - months_ago * 0.011) |> Decimal.round(4)
end

scaled_amount = fn base, months_ago ->
  base
  |> Decimal.mult(scale_for.(months_ago))
  |> Decimal.round(2)
end

historical_transaction = fn account, months_ago, day, hour, attrs ->
  {year, month} = month_offset_at.(months_ago)
  date = Date.new!(year, month, day)
  occurred_at = DateTime.new!(date, Time.new!(hour, 0, 0), "Etc/UTC")
  month_tag = :io_lib.format("~4..0B_~2..0B", [year, month]) |> IO.iodata_to_binary()
  reference_slug = attrs.reference |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
  external_id = "seed_history_#{reference_slug}_#{month_tag}"

  {account,
   Map.merge(
     %{
       external_id: external_id,
       status: "completed",
       amount_currency: account.currency,
       booked_at: occurred_at,
       settled_at: occurred_at,
       provider_updated_at: occurred_at,
       categorized_at: finance_now,
       categorized_by_agent: "seed",
       categorization_confidence: Decimal.new("0.9000"),
       metadata: %{"seed" => true, "history" => true},
       raw: %{"provider" => account.provider}
     },
     Map.put(attrs, :external_id, external_id)
   )}
end

historical_finance_transactions =
  for months_ago <- historical_months do
    [
      # EUR – Qonto Payroll account: monthly salaries
      historical_transaction.(qonto_payroll, months_ago, 22, 9, %{
        direction: "debit",
        kind: "salary",
        counterparty_name: "Deel",
        description: "Monthly payroll",
        reference: "PAYROLL-EUR",
        amount_value: scaled_amount.(Decimal.new("26000.00"), months_ago),
        finance_category_id: finance_categories.payroll.id,
        categorization_reason: "Payroll provider payment"
      }),
      # EUR – Qonto Operating: customer invoice
      historical_transaction.(qonto_operating, months_ago, 23, 8, %{
        direction: "credit",
        kind: "invoice_payment",
        counterparty_name: "Northstar GmbH",
        description: "Customer invoice payment",
        reference: "INV-RECURRING",
        amount_value: scaled_amount.(Decimal.new("18000.00"), months_ago),
        finance_category_id: finance_categories.revenue.id,
        categorization_reason: "Customer invoice payment"
      }),
      # EUR – cloud infra
      historical_transaction.(qonto_operating, months_ago, 16, 10, %{
        direction: "debit",
        kind: "subscription",
        counterparty_name: "Amazon Web Services",
        description: "Infrastructure bill",
        reference: "AWS-RECURRING",
        amount_value: scaled_amount.(Decimal.new("6500.00"), months_ago),
        finance_category_id: finance_categories.cloud_infrastructure.id,
        categorization_reason: "Cloud infrastructure bill"
      }),
      # EUR – rent
      historical_transaction.(qonto_operating, months_ago, 10, 7, %{
        direction: "debit",
        kind: "rent",
        counterparty_name: "Berlin Office Lease",
        description: "HQ rent",
        reference: "RENT-RECURRING",
        amount_value: Decimal.new("4200.00"),
        finance_category_id: finance_categories.rent.id,
        categorization_reason: "Office lease payment"
      }),
      # EUR – software (Linear)
      historical_transaction.(qonto_operating, months_ago, 8, 15, %{
        direction: "debit",
        kind: "subscription",
        counterparty_name: "Linear",
        description: "Engineering tooling",
        reference: "LINEAR-RECURRING",
        amount_value: scaled_amount.(Decimal.new("980.00"), months_ago),
        finance_category_id: finance_categories.software.id,
        categorization_reason: "Engineering SaaS subscription"
      }),
      # EUR – contractors
      historical_transaction.(qonto_operating, months_ago, 22, 13, %{
        direction: "debit",
        kind: "contractor_payment",
        counterparty_name: "Contractor Batch",
        description: "Monthly contractors",
        reference: "CTR-RECURRING",
        amount_value: scaled_amount.(Decimal.new("12800.00"), months_ago),
        finance_category_id: finance_categories.contractors.id,
        categorization_reason: "Contractor batch payment"
      }),
      # USD – payroll (Rippling)
      historical_transaction.(mercury_operating, months_ago, 18, 14, %{
        direction: "debit",
        kind: "outgoing_payment",
        counterparty_name: "Rippling",
        description: "US payroll",
        reference: "PAYROLL-USD",
        amount_value: scaled_amount.(Decimal.new("18500.00"), months_ago),
        finance_category_id: finance_categories.payroll.id,
        categorization_reason: "US payroll provider payment"
      }),
      # USD – AI platform (day 25 keeps us inside February)
      historical_transaction.(mercury_operating, months_ago, 25, 11, %{
        direction: "debit",
        kind: "debit_card_transaction",
        counterparty_name: "OpenAI",
        description: "AI platform spend",
        reference: "OPENAI-RECURRING",
        amount_value: scaled_amount.(Decimal.new("2400.00"), months_ago),
        finance_category_id: finance_categories.software.id,
        categorization_reason: "AI platform software spend"
      }),
      # USD – wire fee (excluded from runway)
      historical_transaction.(mercury_operating, months_ago, 12, 9, %{
        direction: "debit",
        kind: "wire_fee",
        counterparty_name: "Mercury",
        description: "Wire fee",
        reference: "WIRE-FEE",
        amount_value: Decimal.new("15.00"),
        finance_category_id: finance_categories.banking_fees.id,
        categorization_reason: "Bank wire fee",
        affects_runway: false
      })
      | if rem(months_ago, 3) == 0 do
          [
            # USD – annual customer wire (every three months)
            historical_transaction.(mercury_operating, months_ago, 21, 16, %{
              direction: "credit",
              kind: "incoming_domestic_wire",
              counterparty_name: "Acme Inc.",
              description: "Enterprise contract installment",
              reference: "WIRE-ACME",
              amount_value: scaled_amount.(Decimal.new("36000.00"), months_ago),
              finance_category_id: finance_categories.revenue.id,
              categorization_reason: "Enterprise contract wire"
            }),
            # EUR – quarterly tax payment
            historical_transaction.(qonto_operating, months_ago, 3, 11, %{
              direction: "debit",
              kind: "tax",
              counterparty_name: "URSSAF",
              description: "Quarterly social contributions",
              reference: "TAX-Q",
              amount_value: scaled_amount.(Decimal.new("14500.00"), months_ago),
              finance_category_id: finance_categories.taxes.id,
              categorization_reason: "Social contributions tax payment"
            })
          ]
        else
          []
        end
    ]
  end
  |> List.flatten()

for {account, attrs} <- finance_transactions ++ historical_finance_transactions do
  upsert_finance_transaction.(account, attrs)
end

upsert_finance_invoice = fn attrs ->
  {finance_transaction_id, attrs} = Map.pop(attrs, :finance_transaction_id)

  invoice =
    case Repo.get_by(FinanceInvoice, invoice_number: attrs.invoice_number) do
      nil -> %FinanceInvoice{}
      existing -> existing
    end

  invoice
  |> FinanceInvoice.changeset(attrs)
  |> Ecto.Changeset.put_change(:finance_transaction_id, finance_transaction_id)
  |> Repo.insert_or_update!()
end

replace_finance_invoice_line_items = fn invoice, line_items ->
  from(line_item in FinanceInvoiceLineItem, where: line_item.finance_invoice_id == ^invoice.id)
  |> Repo.delete_all()

  Enum.each(line_items, fn attrs ->
    {finance_category_id, attrs} = Map.pop(attrs, :finance_category_id)

    %FinanceInvoiceLineItem{finance_invoice_id: invoice.id}
    |> FinanceInvoiceLineItem.changeset(attrs)
    |> Ecto.Changeset.put_change(:finance_category_id, finance_category_id)
    |> Repo.insert!()
  end)
end

finance_transaction_by_external_id = fn external_id ->
  Repo.get_by!(FinanceTransaction, external_id: external_id)
end

seed_finance_invoice = fn attrs, line_items ->
  invoice = upsert_finance_invoice.(attrs)
  replace_finance_invoice_line_items.(invoice, line_items)
  invoice
end

seed_finance_invoice.(
  %{
    finance_transaction_id: finance_transaction_by_external_id.("seed_qonto_infra_june").id,
    vendor_name: "Amazon Web Services",
    invoice_number: "AWS-2026-06",
    invoice_date: ~D[2026-06-01],
    due_date: ~D[2026-06-30],
    period_start: ~D[2026-06-01],
    period_end: ~D[2026-06-30],
    status: "extracted",
    total_amount_value: Decimal.new("6700.00"),
    total_amount_currency: "EUR",
    tax_amount_value: Decimal.new("0.00"),
    tax_amount_currency: "EUR",
    confidence: Decimal.new("0.9700"),
    extracted_by_agent: "seed",
    extracted_at: finance_now,
    metadata: %{
      "seed" => true,
      "document_source" => "qonto",
      "qonto_transaction_id" => "seed_qonto_infra_june",
      "qonto_attachment_id" => "seed-att-aws-2026-06"
    }
  },
  [
    %{
      finance_category_id: finance_categories.cloud_infrastructure.id,
      description: "Compute workloads",
      cost_type: "compute",
      amount_value: Decimal.new("3900.00"),
      amount_currency: "EUR",
      service_period_start: ~D[2026-06-01],
      service_period_end: ~D[2026-06-30],
      confidence: Decimal.new("0.9800"),
      metadata: %{"seed" => true}
    },
    %{
      finance_category_id: finance_categories.cloud_infrastructure.id,
      description: "Managed databases and storage",
      cost_type: "storage",
      amount_value: Decimal.new("1900.00"),
      amount_currency: "EUR",
      service_period_start: ~D[2026-06-01],
      service_period_end: ~D[2026-06-30],
      confidence: Decimal.new("0.9600"),
      metadata: %{"seed" => true}
    },
    %{
      finance_category_id: finance_categories.cloud_infrastructure.id,
      description: "Observability and data transfer",
      cost_type: "networking",
      amount_value: Decimal.new("900.00"),
      amount_currency: "EUR",
      service_period_start: ~D[2026-06-01],
      service_period_end: ~D[2026-06-30],
      confidence: Decimal.new("0.9400"),
      metadata: %{"seed" => true}
    }
  ]
)

seed_finance_invoice.(
  %{
    finance_transaction_id: finance_transaction_by_external_id.("seed_qonto_support_tools").id,
    vendor_name: "Linear",
    invoice_number: "LINEAR-2026-05",
    invoice_date: ~D[2026-05-01],
    due_date: ~D[2026-05-15],
    period_start: ~D[2026-05-01],
    period_end: ~D[2026-05-31],
    status: "extracted",
    total_amount_value: Decimal.new("980.00"),
    total_amount_currency: "EUR",
    tax_amount_value: Decimal.new("0.00"),
    tax_amount_currency: "EUR",
    confidence: Decimal.new("0.9500"),
    extracted_by_agent: "seed",
    extracted_at: finance_now,
    metadata: %{
      "seed" => true,
      "document_source" => "qonto",
      "qonto_transaction_id" => "seed_qonto_support_tools",
      "qonto_attachment_id" => "seed-att-linear-2026-05"
    }
  },
  [
    %{
      finance_category_id: finance_categories.software.id,
      description: "Engineering project management seats",
      cost_type: "subscription",
      amount_value: Decimal.new("780.00"),
      amount_currency: "EUR",
      service_period_start: ~D[2026-05-01],
      service_period_end: ~D[2026-05-31],
      confidence: Decimal.new("0.9700"),
      metadata: %{"seed" => true}
    },
    %{
      finance_category_id: finance_categories.software.id,
      description: "Workspace automations",
      cost_type: "usage",
      amount_value: Decimal.new("200.00"),
      amount_currency: "EUR",
      service_period_start: ~D[2026-05-01],
      service_period_end: ~D[2026-05-31],
      confidence: Decimal.new("0.9200"),
      metadata: %{"seed" => true}
    }
  ]
)

if Mix.env() == :dev do
  seed_documents_dir = Path.expand("tmp/seed_documents")
  File.mkdir_p!(seed_documents_dir)

  seed_documents = [
    %{
      filename: "tuist-cloud-master-services-agreement.txt",
      document_type: "contract",
      correspondent: "Acme Inc.",
      tags: ["legal", "renewal"],
      document_date: ~D[2026-01-15],
      account_key: "demo:acme",
      title: "Tuist Cloud Master Services Agreement",
      summary:
        "Master services agreement covering Tuist Cloud enterprise terms, data processing, support, and renewal obligations.",
      attributes: %{
        "seed" => true,
        "counterparty" => "Acme Inc.",
        "effective_date" => "2026-01-15",
        "renewal_notice_days" => 60
      },
      content: """
      MASTER SERVICES AGREEMENT

      This Master Services Agreement is entered into by Tuist GmbH and Acme Inc. for Tuist Cloud Enterprise.
      The agreement starts on 2026-01-15 and renews annually unless either party gives sixty days notice.
      Acme receives priority support, hosted build insights, binary cache storage, and access to the
      customer success review cadence.

      Data processing terms require Tuist to keep production customer data encrypted at rest and in transit.
      Subprocessors must be listed before onboarding. Security incidents must be communicated without undue delay.

      \f
      COMMERCIAL TERMS

      The annual subscription is 72,000 EUR, billed quarterly in advance. Late payment gives Tuist the right
      to suspend non-critical services after written notice. The agreement includes a mutual confidentiality
      clause and limits liability to fees paid during the prior twelve months, except for confidentiality and
      data protection obligations.

      \f
      SERVICE LEVEL AGREEMENT

      Tuist will make the hosted Tuist Cloud service available at least 99.9% of each calendar month,
      excluding scheduled maintenance windows announced at least 48 hours in advance.

      Priority 1 support requests submitted through the shared Slack Connect channel or support portal
      receive an initial response within one hour, 24 hours per day and seven days per week.

      If monthly availability falls below 99.9%, Acme may request a service credit equal to 5% of the
      affected monthly subscription fees. Credits are the sole remedy for availability misses and do not
      apply to customer-caused outages, beta features, force majeure events, or scheduled maintenance.
      """,
      service_levels: [
        %{
          name: "Monthly availability",
          category: "availability",
          target: "Tuist Cloud available at least 99.9% of each calendar month.",
          target_value: Decimal.new("99.9"),
          target_unit: "percent",
          measurement_window: "calendar month",
          applies_from: ~D[2026-01-15],
          applies_until: ~D[2027-01-14],
          service_credit: "5% of affected monthly subscription fees below the 99.9% availability target.",
          exclusions:
            "Scheduled maintenance announced at least 48 hours in advance, customer-caused outages, beta features, and force majeure events.",
          source_page: 3,
          source_excerpt:
            "Tuist will make the hosted Tuist Cloud service available at least 99.9% of each calendar month.",
          confidence: Decimal.new("0.95")
        },
        %{
          name: "Priority 1 initial response",
          category: "response_time",
          target: "Priority 1 support requests receive an initial response within one hour.",
          target_value: Decimal.new("1"),
          target_unit: "hour",
          measurement_window: "24x7 support coverage",
          applies_from: ~D[2026-01-15],
          applies_until: ~D[2027-01-14],
          source_page: 3,
          source_excerpt:
            "Priority 1 support requests submitted through the shared Slack Connect channel or support portal receive an initial response within one hour.",
          confidence: Decimal.new("0.92")
        }
      ]
    },
    %{
      filename: "acme-security-evidence-request-2026-05.txt",
      document_type: "security",
      correspondent: "Acme",
      tags: ["security", "soc2", "procurement"],
      document_date: ~D[2026-05-12],
      account_key: "demo:acme",
      title: "Acme Security Evidence Request",
      summary:
        "Acme security and procurement evidence request covering SOC2, subprocessors, data retention, and DPA review items.",
      attributes: %{
        "seed" => true,
        "counterparty" => "Acme",
        "procurement_stage" => "security_review",
        "requested_evidence" => ["soc2", "subprocessors", "data_retention", "dpa"]
      },
      content: """
      SECURITY EVIDENCE REQUEST

      Acme procurement requests the latest Tuist Cloud SOC2 Type II report, current subprocessor list,
      data retention policy, and standard DPA before legal approval. The security contact asked that all
      evidence reference acme.example and the active enterprise evaluation.

      The review is tied to the Acme expansion opportunity and should be answered before the renewal
      committee meets. Open items include SSO enforcement, audit-log retention, and incident notification
      language.
      """
    },
    %{
      filename: "board-pack-2026-q2-runway.txt",
      document_type: "board",
      correspondent: nil,
      tags: ["finance", "runway"],
      document_date: ~D[2026-04-01],
      title: "Q2 2026 Board Pack - Runway and Hiring",
      summary:
        "Board pack covering runway, hiring constraints, enterprise pipeline, and infrastructure cost controls for Q2 2026.",
      attributes: %{
        "seed" => true,
        "period" => "2026-Q2",
        "cash_runway_months" => 18
      },
      content: """
      Q2 2026 BOARD PACK

      Atlas highlights eighteen months of runway under the current hiring plan. The finance view should keep
      Qonto and Mercury balances reconciled weekly, with a focus on infrastructure spend, payroll, contractor
      payments, and customer wire timing.

      Hiring remains limited to senior product engineering and customer success. Any additional role requires
      confirmation that enterprise conversion offsets the monthly burn increase.

      \f
      ENTERPRISE PIPELINE

      Active opportunities include Acme renewal expansion, Acme security review, and a new platform team
      evaluation at Wise. The board asks for a monthly document packet with contracts, invoices, and procurement
      notes available through semantic search so executives can answer questions without digging through paperless.
      """
    },
    %{
      filename: "employment-policy-remote-work.txt",
      document_type: "policy",
      correspondent: nil,
      tags: ["hr", "security"],
      document_date: ~D[2026-03-01],
      title: "Remote Work and Equipment Policy",
      summary:
        "Internal employment policy for remote work expectations, home office equipment, travel approvals, and security handling.",
      attributes: %{
        "seed" => true,
        "policy_owner" => "People Operations",
        "effective_date" => "2026-03-01"
      },
      content: """
      REMOTE WORK AND EQUIPMENT POLICY

      Tuist is a remote-first company. Employees may work from their regular country of employment unless People
      Operations approves a temporary location change. Customer documents, legal files, financial exports, and
      board materials must stay in approved company systems.

      Equipment purchases above 1,500 EUR need executive approval. Lost devices must be reported immediately so
      access can be revoked and the incident can be reviewed.
      """
    },
    %{
      filename: "vendor-invoice-openai-2026-05.txt",
      document_type: "invoice",
      correspondent: "OpenAI",
      tags: ["finance", "software"],
      document_date: ~D[2026-05-01],
      title: "OpenAI Vendor Invoice - May 2026",
      summary: "Vendor invoice for AI platform usage in May 2026, useful for finance categorization and runway review.",
      attributes: %{
        "seed" => true,
        "vendor" => "OpenAI",
        "invoice_month" => "2026-05",
        "amount" => "2400.00",
        "currency" => "USD"
      },
      content: """
      VENDOR INVOICE

      Vendor: OpenAI
      Month: May 2026
      Amount: 2,400.00 USD
      Description: AI platform usage for document classification, account analysis, and Slack response drafting.

      Finance should categorize this invoice as software and AI platform spend. The charge affects runway and
      should be reconciled against the Mercury transaction feed.
      """
    }
  ]

  seed_document_filenames = Enum.map(seed_documents, & &1.filename)

  from(document in Document,
    where:
      document.original_filename in ^seed_document_filenames or
        fragment("?->>'seed' = 'true'", document.attributes)
  )
  |> Repo.delete_all()

  Enum.each(seed_documents, fn seed_document ->
    path = Path.join(seed_documents_dir, seed_document.filename)
    File.write!(path, seed_document.content)

    {:ok, document} =
      Documents.create_from_path(
        path,
        %{
          "original_filename" => seed_document.filename,
          "content_type" => "text/plain",
          "source" => "paperless"
        },
        enqueue?: false
      )

    {:ok, document} =
      Documents.process_document(document.id, classify_fallback?: true)

    correspondent = seed_document.correspondent && Documents.upsert_correspondent(seed_document.correspondent)
    document_type = Documents.upsert_document_type(seed_document.document_type)
    tags = Documents.upsert_tags(seed_document.tags)
    account = seed_document[:account_key] && Repo.get_by(Account, account_key: seed_document.account_key)

    document =
      document
      |> Repo.preload(:tags)
      |> Document.changeset(%{
        title: seed_document.title,
        summary: seed_document.summary,
        attributes: seed_document.attributes,
        document_date: seed_document.document_date,
        status: "ready"
      })
      |> Ecto.Changeset.change(%{
        account_id: account && account.id,
        correspondent_id: correspondent && correspondent.id,
        document_type_id: document_type.id
      })
      |> Ecto.Changeset.put_assoc(:tags, tags)
      |> Repo.update!()

    service_levels = Map.get(seed_document, :service_levels, [])

    if account && service_levels != [] do
      completed_at = ~U[2026-06-01 08:00:00Z]

      check =
        Repo.get_by(ServiceLevelExtractionCheck,
          document_id: document.id,
          agent_version: ServiceLevels.agent_version()
        ) ||
          %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}

      check =
        check
        |> ServiceLevelExtractionCheck.changeset(%{
          agent_version: ServiceLevels.agent_version(),
          document_checksum_sha256: document.checksum_sha256,
          status: "completed",
          started_at: completed_at,
          completed_at: completed_at,
          last_error: nil,
          result_summary: "Seeded service levels extracted from the signed Acme MSA.",
          metadata: %{"seed" => true}
        })
        |> Repo.insert_or_update!()

      from(service_level in ServiceLevel,
        where: service_level.service_level_extraction_check_id == ^check.id
      )
      |> Repo.delete_all()

      for service_level_attrs <- service_levels do
        %ServiceLevel{
          account_id: account.id,
          document_id: document.id,
          service_level_extraction_check_id: check.id
        }
        |> ServiceLevel.changeset(
          service_level_attrs
          |> Map.put(:metadata, %{"seed" => true})
        )
        |> Repo.insert!()
      end
    end
  end)
end

# GTM blog post ideas. Captured from a mix of sources (a teammate in the app,
# Atlas in Slack, and the MCP tools) so the Content backlog shows realistic
# provenance. Author display falls back to created_by_agent when no user is set.
alex_user = Repo.get_by(User, email: "alex@atlas.dev")

demo_blog_post_ideas = [
  %{
    title: "How we cut iOS CI times by 60% with Tuist cache",
    description:
      "Walk through the before/after of enabling binary caching on a large app, with concrete numbers and the gotchas we hit migrating the CI pipeline.",
    status: "in_progress",
    author_id: seed_user.id,
    inserted_at: ~U[2026-05-20 09:30:00Z],
    comments: [
      %{
        body: "Let's anchor this on the dashboard screenshots from the Acme rollout.",
        author_id: alex_user && alex_user.id,
        inserted_at: ~U[2026-05-21 11:00:00Z]
      },
      %{
        body: "Need a callout box on cache key invalidation, it trips everyone up.",
        author_id: seed_user.id,
        inserted_at: ~U[2026-05-23 14:15:00Z]
      }
    ]
  },
  %{
    title: "The hidden cost of a slow build graph",
    description:
      "A founder-facing piece on why build times are a tax on every engineer and how teams quietly lose days each sprint.",
    status: "idea",
    created_by_agent: "slack",
    inserted_at: ~U[2026-05-26 16:45:00Z],
    comments: [
      %{
        body: "Captured from #marketing. Pair with the runway/velocity framing.",
        author_id: alex_user && alex_user.id,
        inserted_at: ~U[2026-05-26 16:50:00Z]
      }
    ]
  },
  %{
    title: "Migrating a 200-module app to Tuist: a field guide",
    description: "Step-by-step migration story aimed at staff engineers evaluating Tuist for a large existing project.",
    status: "idea",
    author_id: seed_user.id,
    inserted_at: ~U[2026-05-28 10:00:00Z],
    comments: []
  },
  %{
    title: "What selective testing actually saves you",
    description:
      "Explain how Tuist skips unaffected tests, with a worked example and the math on CI minutes saved per week.",
    status: "in_progress",
    created_by_agent: "mcp",
    inserted_at: ~U[2026-05-30 13:20:00Z],
    comments: [
      %{
        body: "Get the selective-testing report export from the demo org for the charts.",
        author_id: seed_user.id,
        inserted_at: ~U[2026-05-31 09:05:00Z]
      }
    ]
  },
  %{
    title: "Announcing Tuist Registry: faster dependency resolution",
    description: "Launch post for the registry, covering the motivation, the speedups, and how to opt in.",
    status: "published",
    author_id: alex_user && alex_user.id,
    inserted_at: ~U[2026-04-15 08:00:00Z],
    comments: [
      %{
        body: "Shipped. Keeping this here as a reference for the follow-up benchmarks post.",
        author_id: alex_user && alex_user.id,
        inserted_at: ~U[2026-04-16 12:30:00Z]
      }
    ]
  },
  %{
    title: "Why we bet on a server for Xcode builds",
    description: "Vision piece on the Tuist server: the build cache, insights, and where this is heading.",
    status: "idea",
    created_by_agent: "slack",
    inserted_at: ~U[2026-06-01 17:10:00Z],
    comments: []
  }
]

# Reset only the ideas this script owns so re-running stays idempotent without
# touching ideas captured by hand in dev. Comments cascade on delete.
demo_idea_titles = Enum.map(demo_blog_post_ideas, & &1.title)
from(idea in BlogPostIdea, where: idea.title in ^demo_idea_titles) |> Repo.delete_all()

for idea_attrs <- demo_blog_post_ideas do
  {comments, idea_attrs} = Map.pop(idea_attrs, :comments, [])
  {author_id, idea_attrs} = Map.pop(idea_attrs, :author_id)
  {inserted_at, idea_attrs} = Map.pop(idea_attrs, :inserted_at)
  inserted_at = inserted_at && DateTime.to_naive(inserted_at)

  idea =
    %BlogPostIdea{author_id: author_id, inserted_at: inserted_at, updated_at: inserted_at}
    |> BlogPostIdea.changeset(idea_attrs)
    |> Repo.insert!()

  for comment_attrs <- comments do
    {comment_author_id, comment_attrs} = Map.pop(comment_attrs, :author_id)
    {comment_inserted_at, comment_attrs} = Map.pop(comment_attrs, :inserted_at)
    comment_inserted_at = comment_inserted_at && DateTime.to_naive(comment_inserted_at)

    %BlogPostIdeaComment{
      blog_post_idea_id: idea.id,
      author_id: comment_author_id,
      inserted_at: comment_inserted_at,
      updated_at: comment_inserted_at
    }
    |> BlogPostIdeaComment.changeset(comment_attrs)
    |> Repo.insert!()
  end
end

# GTM social-channel ideas. These mirror how the backlog is used in review:
# quick social angles that can be captured by the dashboard, Slack, or agent tools.
demo_social_channel_ideas = [
  %{
    title: "Turn the cache benchmark chart into a LinkedIn carousel",
    description:
      "Use the before and after build-time chart from the Acme rollout, then end with the practical lesson for platform teams.",
    status: "idea",
    author_id: seed_user.id,
    inserted_at: ~U[2026-06-02 09:45:00Z],
    post_revisions: [
      %{
        body:
          "Build caches are easier to believe when the before and after chart is right in front of you.\n\nSlide 1: the old build time.\nSlide 2: the cached build time.\nSlide 3: what changed in the workflow.\nSlide 4: the platform lesson.",
        notes: "First carousel outline for the benchmark chart.",
        inserted_at: ~U[2026-06-02 10:15:00Z]
      },
      %{
        body:
          "The best cache demo is not a percentage. It is the moment a platform team sees a red bar shrink into room for actual work.\n\nUse the chart, then explain the one workflow decision that made the result repeatable.",
        notes: "Tighter copy for a single LinkedIn post if the carousel is too much.",
        inserted_at: ~U[2026-06-02 14:30:00Z]
      }
    ]
  },
  %{
    title: "Share the selective testing savings as a short launch thread",
    description:
      "Frame the post around skipped unaffected tests and saved developer waiting time. Link to the detailed blog post when it is ready.",
    status: "idea",
    created_by_agent: "mcp",
    inserted_at: ~U[2026-06-03 15:10:00Z],
    post_revisions: [
      %{
        body:
          "Selective testing is not about running fewer tests because you trust them less.\n\nIt is about skipping the tests your change cannot affect, then spending that saved time on feedback that actually matters.",
        notes: "Agent-created first pass from the benchmark summary.",
        created_by_agent: "mcp",
        inserted_at: ~U[2026-06-03 15:20:00Z]
      }
    ]
  },
  %{
    title: "Community prompt: what slows your Xcode project down most?",
    description:
      "Ask the community to pick between indexing, dependency resolution, test selection, and clean builds. Use replies to shape the next guide.",
    status: "idea",
    created_by_agent: "slack",
    inserted_at: ~U[2026-06-04 11:25:00Z],
    post_revisions: [
      %{
        body:
          "What slows your Xcode project down most right now?\n\n1. Indexing\n2. Dependency resolution\n3. Test selection\n4. Clean builds\n\nReply with the one you would fix first.",
        notes: "Poll copy captured from Slack.",
        created_by_agent: "slack",
        inserted_at: ~U[2026-06-04 11:40:00Z]
      }
    ]
  },
  %{
    title: "Clip the registry release note into a founder-facing post",
    description:
      "Explain faster dependency resolution without implementation detail, emphasizing less waiting and fewer broken local setups.",
    status: "approved",
    author_id: alex_user && alex_user.id,
    inserted_at: ~U[2026-06-01 08:20:00Z],
    post_revisions: [
      %{
        body:
          "Dependency resolution is one of those invisible parts of the developer day that only gets noticed when it breaks.\n\nThe registry release makes that path faster and calmer: fewer broken local setups, less waiting, and more predictable starts for new contributors.",
        notes: "Final founder-facing copy.",
        status: "approved",
        inserted_at: ~U[2026-06-01 09:05:00Z]
      }
    ]
  }
]

demo_social_idea_titles = Enum.map(demo_social_channel_ideas, & &1.title)
from(idea in SocialChannelIdea, where: idea.title in ^demo_social_idea_titles) |> Repo.delete_all()

for idea_attrs <- demo_social_channel_ideas do
  {author_id, idea_attrs} = Map.pop(idea_attrs, :author_id)
  {inserted_at, idea_attrs} = Map.pop(idea_attrs, :inserted_at)
  {post_revisions, idea_attrs} = Map.pop(idea_attrs, :post_revisions, [])
  inserted_at = inserted_at && DateTime.to_naive(inserted_at)

  idea =
    %SocialChannelIdea{author_id: author_id, inserted_at: inserted_at, updated_at: inserted_at}
    |> SocialChannelIdea.changeset(idea_attrs)
    |> Repo.insert!()

  post_revisions
  |> Enum.with_index(1)
  |> Enum.each(fn {revision_attrs, revision_number} ->
    {revision_inserted_at, revision_attrs} = Map.pop(revision_attrs, :inserted_at)
    revision_inserted_at = revision_inserted_at && DateTime.to_naive(revision_inserted_at)

    %SocialPostRevision{
      social_channel_idea_id: idea.id,
      author_id: author_id,
      revision_number: revision_number,
      inserted_at: revision_inserted_at,
      updated_at: revision_inserted_at
    }
    |> SocialPostRevision.changeset(revision_attrs)
    |> Repo.insert!()
  end)
end

# Seed representative audit activity so local admin and MCP audit views have
# cross-interface data immediately after setup. The rows are keyed by target,
# action, interface, and timestamp so re-running seeds stays idempotent.
seed_audit_activity = fn attrs ->
  exists? =
    Repo.exists?(
      from activity in Audit.Activity,
        where:
          activity.action == ^attrs.action and
            activity.interface == ^attrs.interface and
            activity.target_type == ^attrs.target_type and
            activity.target_id == ^attrs.target_id and
            activity.occurred_at == ^attrs.occurred_at
    )

  if !exists? do
    {:ok, _activity} =
      Audit.log(attrs.action, Map.put(attrs, :metadata, Map.put(attrs.metadata || %{}, "source", "seed")))
  end
end

seed_audit_targets = %{
  acme: Repo.get_by(Account, account_key: "demo:acme"),
  linear: Repo.get_by(Account, account_key: "demo:linear"),
  selective_testing: Repo.get_by(BlogPostIdea, title: "What selective testing actually saves you"),
  ci_cache: Repo.get_by(BlogPostIdea, title: "How we cut iOS CI times by 60% with Tuist cache")
}

for attrs <- [
      %{
        action: "account.updated",
        interface: "dashboard",
        actor: seed_user,
        occurred_at: ~U[2026-06-01 09:10:00Z],
        target_type: "account",
        target_id: seed_audit_targets.acme && seed_audit_targets.acme.id,
        target_label: seed_audit_targets.acme && seed_audit_targets.acme.name,
        metadata: %{
          "changed" => %{"deal_stage" => "negotiation"},
          "path" => seed_audit_targets.acme && "/sales/accounts/#{seed_audit_targets.acme.id}"
        }
      },
      %{
        action: "mcp.tool_called",
        interface: "mcp",
        actor: Repo.get_by(User, email: "alex@atlas.dev"),
        occurred_at: ~U[2026-06-01 10:30:00Z],
        target_type: "mcp_tool",
        target_id: "list_accounts",
        target_label: "list_accounts",
        metadata: %{"arguments" => %{"query" => "Acme"}, "status" => "ok"}
      },
      %{
        action: "blog_post_idea.created",
        interface: "slack",
        actor: Repo.get_by(User, email: "alex@atlas.dev"),
        occurred_at: ~U[2026-06-01 11:45:00Z],
        target_type: "blog_post_idea",
        target_id: seed_audit_targets.selective_testing && seed_audit_targets.selective_testing.id,
        target_label: seed_audit_targets.selective_testing && seed_audit_targets.selective_testing.title,
        metadata: %{
          "channel" => "#marketing",
          "path" => seed_audit_targets.selective_testing && "/gtm/content/#{seed_audit_targets.selective_testing.id}"
        }
      },
      %{
        action: "account.marked_not_account",
        interface: "worker",
        actor: nil,
        occurred_at: ~U[2026-06-01 13:00:00Z],
        target_type: "account",
        target_id: seed_audit_targets.linear && seed_audit_targets.linear.id,
        target_label: seed_audit_targets.linear && seed_audit_targets.linear.name,
        metadata: %{
          "reason" => "Seeded duplicate suppression example",
          "path" => seed_audit_targets.linear && "/sales/accounts/#{seed_audit_targets.linear.id}"
        }
      },
      %{
        action: "blog_post_idea.updated",
        interface: "dashboard",
        actor: seed_user,
        occurred_at: ~U[2026-06-01 14:20:00Z],
        target_type: "blog_post_idea",
        target_id: seed_audit_targets.ci_cache && seed_audit_targets.ci_cache.id,
        target_label: seed_audit_targets.ci_cache && seed_audit_targets.ci_cache.title,
        metadata: %{
          "changed" => %{"status" => "in_progress"},
          "path" => seed_audit_targets.ci_cache && "/gtm/content/#{seed_audit_targets.ci_cache.id}"
        }
      }
    ],
    attrs.target_id do
  seed_audit_activity.(attrs)
end

# Leadership receives a financial pulse every Monday.
leadership_channel_id =
  Application.get_env(:atlas, :briefs, [])[:leadership_slack_channel_id] || "C012LEADERSHIP"

leadership_subscriptions =
  for cadence <- ["weekly"], into: %{} do
    subscription =
      Repo.get_by(BriefSubscription, audience_key: "leadership", cadence: cadence) ||
        %BriefSubscription{}

    subscription =
      subscription
      |> BriefSubscription.changeset(%{
        label: "Leadership",
        audience_key: "leadership",
        cadence: cadence,
        domains: ["finance"],
        slack_app: "company",
        slack_channel_id: leadership_channel_id,
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })
      |> Repo.insert_or_update!()

    {cadence, subscription}
  end

# Seed one reviewable weekly brief so Slack delivery and agent tools are useful
# before the first scheduled run. Items link to their existing source records.
weekly_subscription = leadership_subscriptions["weekly"]
weekly_end = ~U[2026-06-15 00:00:00Z]
weekly_start = DateTime.add(weekly_end, -7, :day)

seed_brief =
  Repo.get_by(Brief,
    brief_subscription_id: weekly_subscription.id,
    cadence: "weekly",
    period_start: weekly_start
  ) ||
    %Brief{brief_subscription_id: weekly_subscription.id}
    |> Brief.changeset(%{
      cadence: "weekly",
      period_start: weekly_start,
      period_end: weekly_end,
      status: "material",
      headline: "Weekly financial pulse",
      summary:
        "Cash and runway remain the focus for this week's financial pulse. Review the finance overview for the latest balance, burn, and upcoming commitments.",
      attention_budget: 8,
      sensitivity: "restricted",
      generation_mode: "deterministic"
    })
    |> Repo.insert!()

seed_brief_items = [
  %{
    domain: "accounts",
    kind: "risk",
    title: "Acme renewal outcome needs attention",
    detail: "The account outcome is at risk and needs an explicit recovery move before the next customer conversation.",
    severity: "warning",
    sensitivity: "internal",
    materiality_score: Decimal.new("0.84"),
    suggested_action: "Assign the next customer move and update the outcome review.",
    completion_condition: "The outcome has a current review and an owned next step.",
    fingerprint: "seed:accounts:acme-renewal",
    source_path: seed_audit_targets.acme && "/sales/accounts/#{seed_audit_targets.acme.id}",
    due_at: ~U[2026-06-19 17:00:00Z]
  },
  %{
    domain: "finance",
    kind: "concern",
    title: "Review concentrated vendor spend",
    detail:
      "The latest cost window is concentrated in a small number of vendors and should be reviewed before renewal decisions.",
    severity: "warning",
    sensitivity: "restricted",
    materiality_score: Decimal.new("0.76"),
    suggested_action: "Review the largest invoices and record any follow-up owner.",
    completion_condition: "The invoices are reviewed and required follow-ups have owners.",
    fingerprint: "seed:finance:vendor-concentration",
    source_path: "/finance/vendors",
    due_at: ~U[2026-06-19 17:00:00Z]
  },
  %{
    domain: "product",
    kind: "change",
    title: "Confirm communication for shipped work",
    detail: "Release-related work shipped this week. Confirm whether customer-facing communication is complete.",
    severity: "info",
    sensitivity: "internal",
    materiality_score: Decimal.new("0.58"),
    suggested_action: "Confirm the changelog or customer communication owner.",
    completion_condition: "Required release communication is published or explicitly deemed unnecessary.",
    fingerprint: "seed:product:release-communication",
    due_at: ~U[2026-06-22 17:00:00Z]
  }
]

seeded_brief_items =
  seed_brief_items
  |> Enum.with_index()
  |> Map.new(fn {attrs, position} ->
    item =
      Repo.get_by(BriefItem, brief_id: seed_brief.id, fingerprint: attrs.fingerprint) ||
        %BriefItem{brief_id: seed_brief.id}

    item =
      item
      |> BriefItem.changeset(Map.put(attrs, :position, position))
      |> Repo.insert_or_update!()

    {attrs.domain, item}
  end)

seed_repository = Repo.get_by!(GitHubRepository, owner: "tuist", repo: "atlas")

seed_product_trace =
  Repo.get_by(ProductTrace, provider: "github", external_id: "seed:atlas:pull-request:712") ||
    case Product.record_trace(%{
           provider: "github",
           kind: "pull_request_merged",
           external_id: "seed:atlas:pull-request:712",
           github_repository_id: seed_repository.id,
           repository_full_name: "tuist/atlas",
           number: 712,
           title: "Publish account outcome recovery prompts",
           url: "https://github.com/tuist/atlas/pull/712",
           author_login: "morgan",
           occurred_at: ~U[2026-06-12 14:30:00Z],
           labels: ["release", "changelog"],
           sensitivity: "internal"
         }) do
      {:ok, trace} -> trace
      {:error, changeset} -> raise "could not seed product trace: #{inspect(changeset.errors)}"
    end

seeded_brief_items["product"]
|> BriefItem.changeset(%{source_path: seed_product_trace.url})
|> Repo.update!()

{:ok, _evidence_link} =
  Evidence.link(%{
    subject_type: "brief_item",
    subject_id: seeded_brief_items["product"].id,
    record_type: "product_trace",
    record_id: seed_product_trace.id,
    source_class: "observed",
    sensitivity: "internal",
    observation: "Pull request 712 merged with release and changelog labels.",
    position: 0
  })

# Seed feature-usage snapshots for the Tuist-linked demo account so the account
# dashboard's "Feature usage" card and the churn read tools have data locally.
# In production these rows are produced by the daily
# Atlas.FeatureUsage.Workers.ScheduleFeatureUsage fan-out against the Tuist
# ClickHouse proxy; here we synthesize a representative snapshot, including one
# feature ("bundles") that has just stopped, to exercise the alert surface.
feature_usage_account = Repo.get_by(Account, account_key: "demo:acme")

if feature_usage_account do
  computed_at = ~U[2026-07-29 05:30:00Z]

  from(s in Snapshot, where: s.account_id == ^feature_usage_account.id)
  |> Repo.delete_all()

  feature_usage_rows = %{
    "cache" => {300, 1550, 1498, ~U[2026-07-29 04:10:00Z]},
    "selective_testing" => {42, 320, 300, ~U[2026-07-29 03:40:00Z]},
    "sharding" => {14, 92, 80, ~U[2026-07-29 03:10:00Z]},
    "test_analytics" => {51, 410, 380, ~U[2026-07-29 04:05:00Z]},
    "builds" => {64, 480, 450, ~U[2026-07-29 04:20:00Z]},
    "previews" => {6, 44, 39, ~U[2026-07-28 18:00:00Z]},
    "generate" => {9, 61, 58, ~U[2026-07-29 02:15:00Z]},
    # Recently stopped: used the prior week, silent in the last one.
    "bundles" => {0, 0, 22, ~U[2026-07-21 12:00:00Z]},
    "runners" => {0, 0, 0, nil},
    # Configuration feature: 5 automations set up across the account's projects,
    # 3 of them enabled (see Atlas.FeatureUsage.Catalog on how these read).
    "automations" => {5, 3, 0, ~U[2026-07-24 09:30:00Z]},
    # Account-level configuration: single sign-on is configured for Acme.
    "single_sign_on" => {1, 1, 0, ~U[2026-07-23 14:20:00Z]},
    # Build systems in use (rendered as the badge strip, not widgets).
    "system_xcode" => {300, 1620, 1570, ~U[2026-07-29 04:12:00Z]},
    "system_gradle" => {0, 0, 0, nil},
    # Continuous-integration providers seen in recent build and test telemetry.
    "continuous_integration_github" => {42, 320, 300, ~U[2026-07-29 04:18:00Z]},
    "continuous_integration_circleci" => {3, 21, 18, ~U[2026-07-28 18:00:00Z]}
  }

  for {feature, {last_24h, last_7d, prior_7d, last_used_at}} <- feature_usage_rows do
    %Snapshot{}
    |> Snapshot.changeset(%{
      account_id: feature_usage_account.id,
      feature: feature,
      events_last_24h: last_24h,
      events_last_7d: last_7d,
      events_prior_7d: prior_7d,
      last_used_at: last_used_at,
      active: last_7d > 0,
      active_previous: prior_7d > 0,
      computed_at: computed_at
    })
    |> Repo.insert!()
  end
end

# Seed durable Account attention suggestions so the local account view shows
# the founder follow-up flow without invoking the language model or posting to
# Slack. The suggestions cite the same event and usage records that the agent
# receives, and include a snoozed item to demonstrate retained follow-up
# history. The demo-account reset above removes these rows before each run.
account_attention_seeds = [
  %{
    account_key: "demo:acme",
    kind: "adoption",
    topic: "test-sharding-rollout",
    status: "pending",
    title: "Confirm the next team for test sharding",
    rationale:
      "Acme recorded sustained test sharding and automation use, while the renewal-planning meeting kept the sandbox rollout on the same timeline as the analytics add-on.",
    suggested_action:
      "Ask Maya to name the next team and set a date for enabling test sharding in its release workflow.",
    confidence: Decimal.new("0.91"),
    event_evidence: [
      {"not_demo_acme_renewal", "Maya confirmed that the sandbox rollout should stay on the renewal timeline."}
    ],
    usage_evidence: [
      {"sharding", "Test sharding recorded 92 events in the last seven days."},
      {"automations", "Acme has three active automations supporting its release workflow."}
    ],
    posted_at: ~U[2026-08-26 08:00:00Z]
  },
  %{
    account_key: "demo:acme",
    kind: "value_proof",
    topic: "test-selection-renewal-evidence",
    status: "snoozed",
    title: "Bring test-selection results into the renewal conversation",
    rationale:
      "Test selections were used 320 times in the last seven days, and Acme is already considering the analytics add-on as part of the renewal.",
    suggested_action: "Prepare one before-and-after example from the sandbox team for the next renewal check-in.",
    confidence: Decimal.new("0.84"),
    event_evidence: [
      {"not_demo_acme_renewal",
       "The renewal plan includes the analytics add-on and a review of the sandbox rollout results."}
    ],
    usage_evidence: [
      {"selective_testing", "Test selections recorded 320 events in the last seven days."}
    ],
    snoozed_until: ~U[2026-09-02 08:00:00Z],
    posted_at: ~U[2026-08-26 08:00:00Z]
  },
  %{
    account_key: "demo:acme",
    kind: "follow_up",
    topic: "security-packet-before-validation",
    status: "pending",
    title: "Send the security packet before technical validation",
    rationale:
      "Acme's security reviewer requested SSO, audit-log, and data-residency details before the trial can expand, while the platform champion asked for a forwardable written summary.",
    suggested_action:
      "Send Leo the security packet and cache benchmark summary, then ask Priya to confirm a date for the final validation call.",
    confidence: Decimal.new("0.94"),
    event_evidence: [
      {"not_demo_acme_security",
       "Leo requested security details and Priya asked for a forwardable written summary before expansion."}
    ],
    usage_evidence: [],
    posted_at: ~U[2026-08-26 08:00:00Z]
  }
]

for seed <- account_attention_seeds,
    %Account{} = account <- [Repo.get_by(Account, account_key: seed.account_key)] do
  event_evidence =
    Enum.flat_map(seed.event_evidence, fn {external_id, observation} ->
      case Repo.get_by(Event, account_id: account.id, external_id: external_id) do
        %Event{} = event ->
          [
            %{
              "source_type" => "account_event",
              "source_id" => event.id,
              "observation" => observation
            }
          ]

        nil ->
          []
      end
    end)

  usage_evidence =
    Enum.flat_map(seed.usage_evidence, fn {feature, observation} ->
      case Repo.get_by(Snapshot, account_id: account.id, feature: feature) do
        %Snapshot{} = snapshot ->
          [
            %{
              "source_type" => "feature_usage_snapshot",
              "source_id" => snapshot.id,
              "observation" => observation
            }
          ]

        nil ->
          []
      end
    end)

  %AccountAttentionSuggestion{account_id: account.id}
  |> AccountAttentionSuggestion.changeset(%{
    status: seed.status,
    kind: seed.kind,
    suggestion_key: AccountAttentionSuggestion.suggestion_key(seed.kind, seed.topic),
    title: seed.title,
    rationale: seed.rationale,
    suggested_action: seed.suggested_action,
    evidence: %{"items" => event_evidence ++ usage_evidence},
    confidence: seed.confidence,
    generated_by_agent: "account_attention_agent",
    metadata: %{"source" => "seed"}
  })
  |> Ecto.Changeset.change(%{
    snoozed_until: Map.get(seed, :snoozed_until),
    slack_channel_id: "C0SALESDEMO",
    slack_thread_ts: "1787731200.000100",
    posted_at: seed.posted_at
  })
  |> Repo.insert!()
end

# Development-only hardware inventory examples so the Hardware view has
# something meaningful to render in local development. Idempotent by
# asset_tag.
seed_dc =
  case Repo.get_by(DataCenter, name: "TARGO Frankfurt") do
    nil ->
      %DataCenter{}
      |> DataCenter.create_changeset(%{
        name: "TARGO Frankfurt",
        provider: "TARGO Datacenter",
        city: "Frankfurt",
        country: "DE",
        notes: "Primary colocation for the Mac Pro build farm."
      })
      |> Repo.insert!()

    existing ->
      existing
  end

seed_assets = [
  %{
    asset_tag: "DEV-LAP-001",
    serial_number: "C02X-DEMO-001",
    manufacturer: "Apple",
    model: "MacBook Pro 14 M4 Pro",
    name: "Pedro's MacBook Pro",
    category: "laptop",
    specs: %{"cpu" => "Apple M4 Pro", "ram_gb" => 24, "storage_gb" => 1024, "os" => "macOS 15"},
    purchased_on: ~D[2026-01-15],
    acquisition_cost: Decimal.new("3599.00"),
    acquisition_currency: "EUR",
    useful_life_months: 36,
    valuation_treatment: "depreciable",
    location: "home",
    location_detail: "Berlin",
    warranty_end_on: ~D[2027-01-15],
    vendor: "Apple"
  },
  %{
    asset_tag: "DEV-SRV-001",
    serial_number: "TK-DEMO-001",
    manufacturer: "Thomas-Krenn",
    model: "1HE Intel Server RI1112",
    name: "dc01-node-01",
    category: "server",
    specs: %{"cpu" => "Xeon E-2378", "ram_gb" => 128, "storage_gb" => 3840, "hostname" => "dc01-node-01"},
    purchased_on: ~D[2026-02-20],
    acquisition_cost: Decimal.new("4250.00"),
    acquisition_currency: "EUR",
    useful_life_months: 60,
    valuation_treatment: "depreciable",
    location: "data_center",
    location_detail: "R1",
    warranty_end_on: ~D[2029-02-20],
    vendor: "Thomas-Krenn"
  },
  %{
    asset_tag: "DEV-NET-001",
    serial_number: "MS-DEMO-001",
    manufacturer: "MikroTik",
    model: "CRS354-48G-4S+2Q+RM",
    name: "dc01-tor-01",
    category: "network_switch",
    specs: %{"ports" => 48, "uplinks" => "4x10G, 2x40G"},
    purchased_on: ~D[2026-02-20],
    acquisition_cost: Decimal.new("890.00"),
    acquisition_currency: "EUR",
    useful_life_months: 60,
    valuation_treatment: "depreciable",
    location: "data_center",
    location_detail: "R1",
    warranty_end_on: ~D[2027-02-20],
    vendor: "Thomas-Krenn"
  },
  %{
    asset_tag: "TUIST-MP-001",
    serial_number: "APL-MP-DEMO-001",
    manufacturer: "Apple",
    model: "Mac Pro (M5 Ultra, 2026)",
    name: "Mac Pro (build farm 01)",
    category: "desktop",
    specs: %{
      "cpu" => "Apple M5 Ultra (32-core)",
      "gpu" => "80-core",
      "neural_engine_cores" => 64,
      "ram_gb" => 256,
      "storage_gb" => 4096,
      "os" => "macOS 26 (Tahoe)",
      "purpose" => "iOS/macOS build farm"
    },
    purchased_on: ~D[2026-09-08],
    acquisition_cost: Decimal.new("12499.00"),
    acquisition_currency: "EUR",
    useful_life_months: 48,
    valuation_treatment: "depreciable",
    location: "data_center",
    location_detail: "R1-U1",
    warranty_end_on: ~D[2029-09-08],
    vendor: "Apple"
  },
  %{
    asset_tag: "TUIST-MP-002",
    serial_number: "APL-MP-DEMO-002",
    manufacturer: "Apple",
    model: "Mac Pro (M5 Ultra, 2026)",
    name: "Mac Pro (build farm 02)",
    category: "desktop",
    specs: %{
      "cpu" => "Apple M5 Ultra (32-core)",
      "gpu" => "80-core",
      "neural_engine_cores" => 64,
      "ram_gb" => 256,
      "storage_gb" => 4096,
      "os" => "macOS 26 (Tahoe)",
      "purpose" => "iOS/macOS build farm"
    },
    purchased_on: ~D[2026-09-08],
    acquisition_cost: Decimal.new("12499.00"),
    acquisition_currency: "EUR",
    useful_life_months: 48,
    valuation_treatment: "depreciable",
    location: "data_center",
    location_detail: "R1-U2",
    warranty_end_on: ~D[2029-09-08],
    vendor: "Apple"
  },
  %{
    asset_tag: "TUIST-MP-003",
    serial_number: "APL-MP-DEMO-003",
    manufacturer: "Apple",
    model: "Mac Pro (M5 Ultra, 2026)",
    name: "Mac Pro (build farm 03)",
    category: "desktop",
    specs: %{
      "cpu" => "Apple M5 Ultra (32-core)",
      "gpu" => "80-core",
      "neural_engine_cores" => 64,
      "ram_gb" => 256,
      "storage_gb" => 4096,
      "os" => "macOS 26 (Tahoe)",
      "purpose" => "iOS/macOS build farm"
    },
    purchased_on: ~D[2026-09-08],
    acquisition_cost: Decimal.new("12499.00"),
    acquisition_currency: "EUR",
    useful_life_months: 48,
    valuation_treatment: "depreciable",
    location: "data_center",
    location_detail: "R1-U3",
    warranty_end_on: ~D[2029-09-08],
    vendor: "Apple"
  },
  %{
    asset_tag: "TUIST-MP-004",
    serial_number: "APL-MP-DEMO-004",
    manufacturer: "Apple",
    model: "Mac Pro (M5 Ultra, 2026)",
    name: "Mac Pro (build farm 04)",
    category: "desktop",
    specs: %{
      "cpu" => "Apple M5 Ultra (32-core)",
      "gpu" => "80-core",
      "neural_engine_cores" => 64,
      "ram_gb" => 256,
      "storage_gb" => 4096,
      "os" => "macOS 26 (Tahoe)",
      "purpose" => "iOS/macOS build farm"
    },
    purchased_on: ~D[2026-09-08],
    acquisition_cost: Decimal.new("12499.00"),
    acquisition_currency: "EUR",
    useful_life_months: 48,
    valuation_treatment: "depreciable",
    location: "data_center",
    location_detail: "R1-U4",
    warranty_end_on: ~D[2029-09-08],
    vendor: "Apple"
  }
]

for attrs <- seed_assets do
  attrs =
    if Map.get(attrs, :location) == "data_center" do
      Map.put(attrs, :data_center_id, seed_dc.id)
    else
      attrs
    end

  case Repo.get_by(Asset, asset_tag: attrs.asset_tag) do
    nil ->
      %Asset{}
      |> Asset.create_changeset(attrs)
      |> Repo.insert!()

    %Asset{} ->
      :ok
  end
end

seed_policy =
  case Repo.get_by(InsurancePolicy, provider: "Alte Leipziger", product: "Elektronikversicherung") do
    nil ->
      %InsurancePolicy{}
      |> InsurancePolicy.create_changeset(%{
        provider: "Alte Leipziger",
        product: "Elektronikversicherung",
        currency: "EUR",
        sum_insured: Decimal.new("100000.00"),
        provisional_cover_pct: 50,
        annual_premium: Decimal.new("416.50"),
        premium_frequency: "annual",
        deductible_per_claim: Decimal.new("250.00"),
        deductible_cap: Decimal.new("5000.00"),
        mobile_use_pct: 50,
        cleanup_pct: 10,
        cleanup_min: Decimal.new("10000.00"),
        cleanup_max: Decimal.new("100000.00"),
        movement_pct: 10,
        movement_min: Decimal.new("10000.00"),
        movement_max: Decimal.new("100000.00"),
        covers_data: true,
        covers_software: true,
        covers_dongles: true,
        covers_leased: true,
        covers_third_party_owned: true,
        quote_valid_until: ~D[2026-09-21],
        status: "quoted",
        notes: """
        Quote received 2026-09-07, valid for 14 days.

        Conditional on four confirmations from Filip:
        - leased/third-party-owned equipment coverage
        - Alte Leipziger issuing Versicherungsbestätigung for TARGO
        - colocation site addable later without re-underwriting
        - AVB conditions confirm "loss" is covered, not just theft
        """
      })
      |> Repo.insert!()

    existing ->
      existing
  end

for tag <- [
      "TUIST-MP-001",
      "TUIST-MP-002",
      "TUIST-MP-003",
      "TUIST-MP-004",
      "DEV-SRV-001",
      "DEV-NET-001"
    ] do
  with %Asset{} = asset <- Repo.get_by(Asset, asset_tag: tag),
       nil <- Repo.get_by(InsuranceMember, policy_id: seed_policy.id, asset_id: asset.id) do
    %InsuranceMember{}
    |> InsuranceMember.create_changeset(%{
      policy_id: seed_policy.id,
      asset_id: asset.id,
      declared_value: asset.acquisition_cost,
      covered_from: ~D[2026-09-07]
    })
    |> Repo.insert!()
  end
end

# Shared Markdown notes for exploring the notes dashboard, API, and MCP tools.
# Matching on content keeps this block idempotent when the development database
# is reseeded.
seed_notes = [
  %{
    content: """
    # Atlas Engineering Handbook

    A small collection of operational conventions for the team.

    ## Working agreements

    - Prefer domain boundaries for business actions.
    - Record important actions in the audit trail.
    - Keep customer and operational context searchable.
    """
  },
  %{
    content: """
    # Product Launch Notes

    A demo note for coordinating a release from planning through follow-up.

    ## Checklist

    1. Confirm the rollout owner and success signal.
    2. Share the customer-facing announcement.
    3. Review adoption and support feedback after launch.
    """
  },
  %{
    content: """
    # Customer Escalation Playbook

    Use this note when a customer issue needs coordinated attention.

    ## First response

    Capture the impact, affected accounts, current workaround, and next update time.
    Link relevant evidence in the timeline before assigning a follow-up owner.
    """
  }
]

for attrs <- seed_notes do
  case Repo.get_by(Note, content: attrs.content) do
    nil ->
      {:ok, _note} = Notes.create_note(attrs, seed_user, interface: "system", audit_actor: seed_user)

    %Note{} ->
      :ok
  end
end

# ---------------------------------------------------------------------------
# Inference relay: seed a couple of upstream providers and profiles so the
# /admin/inference pages have something to show without needing a real API
# key configured.
# ---------------------------------------------------------------------------

seed_providers = [
  %{
    key: "openai",
    base_url: "https://api.openai.com/v1",
    api_key: "sk-seed-openai-placeholder",
    timeout: 300_000
  },
  %{
    key: "fireworks",
    base_url: "https://api.fireworks.ai/inference/v1",
    api_key: "fw-seed-placeholder",
    timeout: 300_000
  }
]

for attrs <- seed_providers do
  case Inference.get_provider_by_key(attrs.key) do
    nil -> {:ok, _provider} = Inference.create_provider(attrs)
    %Provider{} -> :ok
  end
end

seed_profiles = [
  %{
    name: "atlas-inference",
    description: "Default profile Atlas uses for its own inference calls.",
    upstream_provider: "openai",
    upstream_model: "gpt-4o-mini",
    input_cost_per_million: Decimal.new("0.15"),
    output_cost_per_million: Decimal.new("0.60"),
    enabled: true,
    atlas_inference: true
  },
  %{
    name: "atlas-coding",
    description: "Profile Atlas uses for coding assistants.",
    upstream_provider: "fireworks",
    upstream_model: "accounts/fireworks/models/kimi-k2p5",
    input_cost_per_million: Decimal.new("0.60"),
    output_cost_per_million: Decimal.new("2.50"),
    enabled: true,
    atlas_coding: true
  },
  %{
    name: "atlas-embeddings",
    description: "Profile Atlas uses for embeddings.",
    upstream_provider: "openai",
    upstream_model: "text-embedding-3-small",
    input_cost_per_million: Decimal.new("0.02"),
    output_cost_per_million: Decimal.new("0.00"),
    enabled: true,
    atlas_embedding: true
  }
]

for attrs <- seed_profiles do
  case Inference.get_model_binding_by_name(attrs.name) do
    nil ->
      {:ok, profile} = Inference.create_profile(attrs)
      # Give each atlas role profile a persistent token so the token page
      # renders end-to-end without an operator having to click through the UI
      # right after seeding.
      role =
        cond do
          profile.atlas_inference -> :inference
          profile.atlas_coding -> :coding
          profile.atlas_embedding -> :embedding
          true -> nil
        end

      if role, do: {:ok, _} = Inference.ensure_atlas_token(profile, role)

    %ModelBinding{} ->
      :ok
  end
end

# Engineering surface: projects, reusable domains, and a plausible error
# stream. This makes /engineering/{projects,domains,errors} render with real
# rows on a fresh local database. The projects also mint a default DSN via
# `Atlas.Engineering.Errors.ensure_default_key/1` inside `create_project/1`.
engineering_project_fixtures = [
  %{
    name: "Tuist CLI",
    description: "Developer tooling for Xcode projects, caching, and CI.",
    visibility: :public
  },
  %{
    name: "Tuist Server",
    description: "The Elixir/Phoenix server behind tuist.dev.",
    visibility: :public
  },
  %{
    name: "Atlas",
    description: "Internal ops app: CRM, contracts, finance, and MCP tools.",
    visibility: :private
  },
  %{
    name: "Kura",
    description: "Distributed cache mesh serving REAPI clients.",
    visibility: :public
  }
]

engineering_projects =
  Enum.map(engineering_project_fixtures, fn attrs ->
    case Repo.get_by(EngineeringProject, name: attrs.name) do
      nil ->
        {:ok, project} = EngineeringProjects.create_project(attrs)
        project

      %EngineeringProject{} = existing ->
        {:ok, project} = EngineeringProjects.update_project(existing, attrs)
        _ = EngineeringErrors.ensure_default_key(project)
        project
    end
  end)

engineering_domain_fixtures = [
  %{
    name: "Cache",
    description: "Binary caching and remote execution.",
    project_names: ["Tuist CLI", "Tuist Server", "Kura"]
  },
  %{name: "Generated projects", description: "Xcode project generation.", project_names: ["Tuist CLI"]},
  %{name: "Registry", description: "Swift package registry.", project_names: ["Tuist Server"]}
]

Enum.each(engineering_domain_fixtures, fn %{project_names: project_names} = fixture ->
  attrs = Map.take(fixture, [:name, :description])

  domain =
    case Repo.get_by(EngineeringDomain, name: fixture.name) do
      nil ->
        {:ok, domain} = EngineeringDomains.create_domain(attrs)
        domain

      %EngineeringDomain{} = existing ->
        existing
    end

  for project_name <- project_names,
      project = Enum.find(engineering_projects, &(&1.name == project_name)) do
    EngineeringDomains.link_domain_to_project(domain, project.id)
  end
end)

# Seed a plausible set of error issues so the errors dashboard has content.
# `Atlas.Engineering.Errors.Issue.deterministic_id/3` makes inserts idempotent
# from the (project_id, domain_id, fingerprint) triple.
now = DateTime.utc_now()

issue_fixtures = [
  %{
    project: "Tuist CLI",
    title: "ArgumentError: invalid path",
    culprit: "TuistKit.Command.run/1",
    level: :error,
    platform: "swift",
    status: :unresolved,
    event_count: 128,
    hours_ago_first: 96,
    hours_ago_last: 1
  },
  %{
    project: "Tuist CLI",
    title: "FileNotFound: Project.swift",
    culprit: "ProjectDescription.load/1",
    level: :error,
    platform: "swift",
    status: :unresolved,
    event_count: 42,
    hours_ago_first: 72,
    hours_ago_last: 3
  },
  %{
    project: "Tuist CLI",
    title: "Xcode 16.4 workspace parser regression",
    culprit: "XcodeProj.Workspace.parse/1",
    level: :warning,
    platform: "swift",
    status: :ignored,
    event_count: 9,
    hours_ago_first: 480,
    hours_ago_last: 24
  },
  %{
    project: "Tuist Server",
    title: "Ecto.ConstraintError on projects_name_index",
    culprit: "TuistWeb.ProjectsController.create/2",
    level: :error,
    platform: "elixir",
    status: :resolved,
    event_count: 3,
    hours_ago_first: 240,
    hours_ago_last: 200
  },
  %{
    project: "Tuist Server",
    title: "Postgrex.Error: too_many_connections",
    culprit: "Tuist.Repo.checkout/1",
    level: :fatal,
    platform: "elixir",
    status: :unresolved,
    event_count: 512,
    hours_ago_first: 12,
    hours_ago_last: 0
  },
  %{
    project: "Tuist Server",
    title: "Jason.DecodeError: unexpected end of input",
    culprit: "TuistWeb.WebhooksController.handle/2",
    level: :warning,
    platform: "elixir",
    status: :unresolved,
    event_count: 76,
    hours_ago_first: 48,
    hours_ago_last: 2
  },
  %{
    project: "Tuist Server",
    title: "Oban.Worker timeout on BuildProcessor",
    culprit: "Tuist.Processor.BuildProcessor.perform/1",
    level: :error,
    platform: "elixir",
    status: :unresolved,
    event_count: 21,
    hours_ago_first: 30,
    hours_ago_last: 4
  },
  %{
    project: "Atlas",
    title: "Broken CSV import for finance transactions",
    culprit: "Atlas.Finance.import_csv/1",
    level: :error,
    platform: "elixir",
    status: :resolved,
    event_count: 4,
    hours_ago_first: 360,
    hours_ago_last: 300
  },
  %{
    project: "Atlas",
    title: "Slack signature verification failed",
    culprit: "Atlas.Slack.verify_signature/2",
    level: :warning,
    platform: "elixir",
    status: :unresolved,
    event_count: 17,
    hours_ago_first: 60,
    hours_ago_last: 6
  },
  %{
    project: "Atlas",
    title: "MCP tool timed out: search_atlas",
    culprit: "Atlas.MCP.Search.run/2",
    level: :warning,
    platform: "elixir",
    status: :unresolved,
    event_count: 33,
    hours_ago_first: 24,
    hours_ago_last: 1
  },
  %{
    project: "Kura",
    title: "gRPC UNAVAILABLE from peer kura-scw-fr-par",
    culprit: "Kura.Mesh.pull/2",
    level: :error,
    platform: "rust",
    status: :unresolved,
    event_count: 205,
    hours_ago_first: 18,
    hours_ago_last: 0
  },
  %{
    project: "Kura",
    title: "REAPI FindMissingBlobs shed under memory pressure",
    culprit: "Kura.Capacity.admit/1",
    level: :warning,
    platform: "rust",
    status: :unresolved,
    event_count: 89,
    hours_ago_first: 8,
    hours_ago_last: 0
  },
  %{
    project: "Kura",
    title: "Snapshot gate denied",
    culprit: "Kura.Snapshots.gate/1",
    level: :info,
    platform: "rust",
    status: :ignored,
    event_count: 12,
    hours_ago_first: 200,
    hours_ago_last: 48
  },
  %{
    project: "Tuist CLI",
    title: "Swift Package Manager resolution deadlock",
    culprit: "SwifterPM.resolve/1",
    level: :error,
    platform: "swift",
    status: :unresolved,
    event_count: 6,
    hours_ago_first: 36,
    hours_ago_last: 8
  },
  %{
    project: "Tuist Server",
    title: "ClickHouse Ecto insert rejected on projection",
    culprit: "Tuist.IngestRepo.insert_all/2",
    level: :error,
    platform: "elixir",
    status: :resolved,
    event_count: 2,
    hours_ago_first: 500,
    hours_ago_last: 450
  }
]

Enum.each(issue_fixtures, fn fixture ->
  project = Enum.find(engineering_projects, &(&1.name == fixture.project))

  if project do
    fingerprint =
      :crypto.hash(:sha256, project.name <> ":" <> fixture.title)
      |> Base.encode16(case: :lower)

    first_seen = DateTime.add(now, -fixture.hours_ago_first * 3600, :second)
    last_seen = DateTime.add(now, -fixture.hours_ago_last * 3600, :second)

    attrs = %{
      project_id: project.id,
      fingerprint: fingerprint,
      title: fixture.title,
      culprit: fixture.culprit,
      level: fixture.level,
      platform: fixture.platform,
      status: fixture.status,
      first_seen: first_seen,
      last_seen: last_seen,
      event_count: fixture.event_count,
      resolved_at: if(fixture.status == :resolved, do: last_seen)
    }

    id = ErrorsIssue.deterministic_id(project.id, fingerprint)

    case Repo.get(ErrorsIssue, id) do
      nil -> %ErrorsIssue{}
      existing -> existing
    end
    |> ErrorsIssue.changeset(attrs)
    |> Repo.insert_or_update!()
  end
end)

# A couple of completed summary runs so the summaries panel isn't empty.
summary_run_fixtures = [
  %{
    hours_ago: 24,
    summary:
      "Postgrex too_many_connections dominated the last 24h, followed by gRPC UNAVAILABLE errors from the kura-scw-fr-par peer. One CLI regression on Xcode 16.4 workspace parsing was silenced.",
    issue_titles: [
      "Postgrex.Error: too_many_connections",
      "gRPC UNAVAILABLE from peer kura-scw-fr-par",
      "ArgumentError: invalid path"
    ]
  },
  %{
    hours_ago: 48,
    summary:
      "Two new spike patterns emerged: Slack signature verification failures on Atlas webhooks and REAPI FindMissingBlobs sheds under memory pressure in Kura. No new fatal issues.",
    issue_titles: [
      "Slack signature verification failed",
      "REAPI FindMissingBlobs shed under memory pressure",
      "Jason.DecodeError: unexpected end of input"
    ]
  }
]

issue_id_by_title =
  from(i in ErrorsIssue, select: {i.title, i.id})
  |> Repo.all()
  |> Map.new()

Enum.each(summary_run_fixtures, fn fixture ->
  scheduled_for =
    now
    |> DateTime.add(-fixture.hours_ago * 3600, :second)
    |> DateTime.truncate(:second)

  issue_ids =
    fixture.issue_titles
    |> Enum.map(&Map.get(issue_id_by_title, &1))
    |> Enum.reject(&is_nil/1)

  fingerprint =
    :crypto.hash(:sha256, "summary:" <> Integer.to_string(fixture.hours_ago))
    |> Base.encode16(case: :lower)

  attrs = %{
    scheduled_for: scheduled_for,
    window_start: DateTime.add(scheduled_for, -24 * 3600, :second),
    window_end: scheduled_for,
    input_fingerprint: fingerprint,
    issue_ids: issue_ids,
    issue_count: length(issue_ids),
    status: :delivered,
    summary: fixture.summary,
    attention: [],
    slack_channel_id: "C0ATLASENG",
    slack_message_ts: "#{System.system_time(:second)}.000100",
    generated_at: scheduled_for,
    delivered_at: scheduled_for
  }

  case Repo.get_by(ErrorsSummaryRun, scheduled_for: scheduled_for) do
    nil -> %ErrorsSummaryRun{}
    existing -> existing
  end
  |> ErrorsSummaryRun.changeset(attrs)
  |> Repo.insert_or_update!()
end)

# Engineering postmortems: seed a couple of published incidents so the
# /engineering/postmortems index has real content on a fresh local DB.
postmortem_author = Repo.get_by(User, email: "alex@atlas.dev")
cache_domain = Repo.get_by(EngineeringDomain, name: "Cache")
registry_domain = Repo.get_by(EngineeringDomain, name: "Registry")

postmortem_fixtures = [
  %{
    body: """
    # Cache mesh partial partition — 2026-08-22

    ## Summary
    A Kura peer in `fsn1` stopped serving `GetActionResult` for ~14 minutes
    after a memory-pressure eviction cascade denied its snapshot gate.

    ## Impact
    CI runs on affected accounts saw REAPI `NOT_FOUND` on warm actions and
    fell back to local execution. No data was lost.

    ## Root cause
    The snapshot gate refused to serve digests whose blobs had been evicted
    by the LRU sweep in the same tick. The gate is a backstop, but the
    eviction cascade was not atomic across gate + storage.

    ## Resolution
    Made the eviction cascade atomic. Kept the gates as a defense in depth.
    """,
    visibility: :public,
    domain_ids: [cache_domain && cache_domain.id]
  },
  %{
    body: """
    # Swift registry publish failure — 2026-09-04

    ## Summary
    Package publishes silently corrupted xcframeworks by flattening
    symlinks in the archive writer.

    ## Impact
    Consumers of a handful of packages hit `a sealed resource is missing
    or invalid` at codesign verification, blocking release builds.

    ## Root cause
    `:zip.create` does not preserve symlinks. The writer path had no
    coverage for signed bundles.

    ## Resolution
    Switched the writer to a symlink-preserving path and backfilled the
    affected releases.
    """,
    visibility: :public,
    domain_ids: [registry_domain && registry_domain.id]
  },
  %{
    body: """
    # Draft: preview migration credential leak

    Draft postmortem being written up. Do not share externally.
    """,
    visibility: :private,
    domain_ids: []
  }
]

if postmortem_author do
  Enum.each(postmortem_fixtures, fn attrs ->
    domain_ids = attrs.domain_ids |> Enum.reject(&is_nil/1)

    payload = %{
      "body" => attrs.body,
      "visibility" => Atom.to_string(attrs.visibility),
      "domain_ids" => Enum.map(domain_ids, &to_string/1)
    }

    first_line = payload["body"] |> String.split("\n", parts: 2) |> hd() |> String.trim_leading("# ")

    already_seeded? =
      Postmortems.list_postmortems(postmortem_author)
      |> Enum.any?(fn pm ->
        pm.body |> String.split("\n", parts: 2) |> hd() |> String.trim_leading("# ") == first_line
      end)

    if !already_seeded? do
      {:ok, _postmortem} = Postmortems.publish_postmortem(payload, postmortem_author)
    end
  end)
end

# Engineering specs: seed a couple of proposals so the /engineering/specs
# index has real content on a fresh local DB.
spec_author = Repo.get_by(User, email: "alex@atlas.dev")
seed_project = Repo.one(from(project in EngineeringProject, limit: 1))

spec_fixtures = [
  %{
    title: "Cross-domain claims v2",
    body: """
    # Cross-domain claims v2

    ## Motivation
    Reviewers want a way to say "these two records refer to the same thing"
    without merging domains.

    ## Design
    Introduce a lightweight claim linking two records across domains, with an
    evidence class the brief renderer can filter on.
    """,
    summary: "Link two records across domains without a merge.",
    visibility: :public,
    status: "proposed"
  },
  %{
    title: "Draft: kura pull replication rollout",
    body: """
    # Draft: kura pull replication rollout

    Not ready for review. Placeholder while the outbox drain design settles.
    """,
    summary: nil,
    visibility: :private,
    status: "draft"
  }
]

if spec_author && seed_project do
  Enum.each(spec_fixtures, fn attrs ->
    payload = %{
      "title" => attrs.title,
      "body" => attrs.body,
      "summary" => attrs.summary,
      "status" => attrs.status,
      "visibility" => Atom.to_string(attrs.visibility),
      "engineering_project_id" => seed_project.id
    }

    already_seeded? =
      Specs.list_specs(user: spec_author)
      |> Enum.any?(fn spec -> spec.title == attrs.title end)

    if !already_seeded? do
      {:ok, _spec} = Specs.create_spec(payload, spec_author)
    end
  end)
end
