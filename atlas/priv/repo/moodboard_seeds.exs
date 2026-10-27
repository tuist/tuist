# Run with: mix run --no-start priv/repo/moodboard_seeds.exs

alias Atlas.Moodboard
alias Atlas.Moodboard.Resource
alias Atlas.Repo
alias Atlas.Search
alias Atlas.Users.User

if Mix.env() != :dev, do: raise("Moodboard preview seeds are development-only")

if !Process.whereis(Repo) do
  {:ok, _} = Application.ensure_all_started(:ecto_sql)
  {:ok, _} = Repo.start_link()
end

if !Process.whereis(Oban) do
  {:ok, _} = Application.ensure_all_started(:oban)
  config = Application.fetch_env!(:atlas, Oban) |> Keyword.merge(testing: :manual, queues: false, plugins: false)
  {:ok, _} = Oban.start_link(config)
end

resources = [
  %{
    title: "Linear: calm, focused product design",
    url: "https://linear.app/",
    description: "A reference for restrained typography, thoughtful motion, and making complex workflows feel simple.",
    image_url: "https://linear.app/api/og/main?title=Linear&v=4",
    tags: ["interfaces", "motion", "websites"]
  },
  %{
    title: "Stripe: explain the complex, beautifully",
    url: "https://stripe.com/",
    description:
      "Explore the hierarchy, product storytelling, gradients, and interactive details across the marketing site.",
    image_url: "https://b.stripecdn.com/mkt-ssr-statics/assets/_next/static/media/stripe.37119086.jpg",
    tags: ["websites", "color", "storytelling"]
  },
  %{
    title: "Radix Colors",
    url: "https://www.radix-ui.com/colors",
    description:
      "Accessible color scales with light and dark variants. Useful when thinking about semantic design tokens.",
    image_url: "https://www.radix-ui.com/colors/opengraph-image.png?opengraph-image.3oqi0y1czcw-9.png",
    tags: ["color", "accessibility", "design-systems"]
  },
  %{
    title: "Recent: a daily dose of web inspiration",
    url: "https://recent.design/",
    description:
      "A collection of distinctive websites to browse when a layout, interaction, or visual direction needs a fresh perspective.",
    image_url: "https://recent.design/og.png",
    tags: ["inspiration", "websites", "motion"]
  },
  %{
    title: "Fonts In Use",
    url: "https://fontsinuse.com/",
    description:
      "Typography in the real world: editorial layouts, identities, packaging, and unexpected type pairings.",
    tags: ["typography", "branding", "editorial"]
  },
  %{
    title: "Laws of UX",
    url: "https://lawsofux.com/",
    description: "A visual introduction to the psychology behind good interfaces. Handy context for a design critique.",
    image_url: "https://lawsofux.com/home/social.en.png",
    tags: ["interfaces", "learning", "accessibility"]
  },
  %{
    title: "Coolors: find the next palette",
    url: "https://coolors.co/",
    description: "Generate and explore color palettes, then bring a few unexpected combinations back to the team.",
    image_url: "https://coolors.co/assets/img/og_image.png",
    tags: ["color", "tools", "inspiration"]
  },
  %{
    title: "Geist: Vercel's design system",
    url: "https://vercel.com/geist/introduction",
    description:
      "A reference for developer-tool interfaces, systematic spacing, clear components, and understated visual language.",
    tags: ["design-systems", "interfaces", "typography"]
  },
  %{
    title: "Designing for reduced motion",
    url: "https://web.dev/articles/prefers-reduced-motion",
    description:
      "A text-heavy reference for making motion optional without losing meaning. Worth reading before our next interaction review.",
    tags: ["articles", "motion", "accessibility"]
  },
  %{
    title: "Sora: motion, pacing, and visual storytelling",
    url: "https://x.com/OpenAI/status/1758192957386342435",
    description:
      "A public X video to try automatic poster and MP4 discovery. Look at the pacing and transitions, not just the individual frames.",
    tags: ["video", "motion", "storytelling"]
  },
  %{
    title: "A prompt for the next design critique",
    content:
      "Start with what the person is trying to do.\n\nWhat is the one action this screen should make obvious? What can wait until it is needed? What could we remove without losing meaning?\n\nDescribe the trade-off before proposing a new component.",
    description: "An original text entry rather than a link. A small reminder to talk about intent before pixels.",
    tags: ["text", "critique", "principles"]
  }
]

{:ok, _} =
  Repo.transaction(fn ->
    users =
      Enum.map(
        [
          %{email: "test@atlas.dev", name: "Test User"},
          %{email: "alex@atlas.dev", name: "Alex Rivera"},
          %{email: "morgan@atlas.dev", name: "Morgan Chen"},
          %{email: "sam@atlas.dev", name: "Sam Okafor"}
        ],
        fn attrs ->
          Repo.get_by(User, email: attrs.email) ||
            Repo.insert!(User.changeset(%User{}, attrs))
        end
      )

    resources
    |> Enum.with_index()
    |> Enum.each(fn {attrs, index} ->
      existing =
        if attrs[:url], do: Repo.get_by(Resource, url: attrs.url), else: Repo.get_by(Resource, title: attrs.title)

      resource =
        case existing do
          nil ->
            {:ok, resource} =
              Moodboard.create_resource(attrs, Enum.at(users, rem(index, length(users))), interface: "system")

            resource

          resource ->
            if resource.url && resource.created_by_id && is_nil(resource.preview_revision) do
              owner = Repo.get!(User, resource.created_by_id)
              {:ok, resource} = Moodboard.refresh_preview(resource.id, owner, interface: "system")
              resource
            else
              Search.with_deferred_vectors(fn -> {:ok, _} = Search.index_moodboard_resource(resource) end)
              resource
            end
        end

      if attrs.title in ["Designing for reduced motion", "A prompt for the next design critique"] do
        {comments, _} = Moodboard.list_comments(hd(users), resource.id, limit: 1)

        if comments == [] do
          {:ok, _} =
            Moodboard.add_comment(
              resource.id,
              %{
                body:
                  "This would be a useful starting point for our next critique. What would we keep, and what would we simplify?"
              },
              Enum.at(users, 1),
              interface: "system"
            )

          {:ok, _} =
            Moodboard.add_comment(
              resource.id,
              %{body: "I'd start with the main action, then check whether the supporting detail earns its place."},
              Enum.at(users, 2),
              interface: "system"
            )
        end
      end
    end)
  end)

IO.puts("Moodboard preview ready: #{Repo.aggregate(Resource, :count)} resources. Use 'Log in as test user' to browse.")
