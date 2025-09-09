defmodule TuistWeb.Marketing.MarketingController do
  use TuistWeb, :controller

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Changelog
  alias Tuist.Marketing.Newsletter
  alias Tuist.Marketing.Pages
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Marketing.Localization

  plug(:assign_default_head_tags)
  plug(:put_resp_header_cache_control)
  plug(:put_resp_header_server)

  def qa(conn, _params) do
    read_more_posts = Enum.take(Blog.get_posts(), 3)
    testimonials = home_testimonials()

    conn
    |> assign(:head_title, "Tuist · A virtual platform team for mobile devs who ship")
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/home.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign_structured_data(get_testimonials_structured_data(testimonials))
    |> assign(:testimonials, testimonials)
    |> assign(:read_more_posts, read_more_posts)
    |> render(:home, layout: false)
  end

  def home(conn, _params) do
    read_more_posts = Enum.take(Blog.get_posts(), 3)
    testimonials = home_testimonials()

    conn
    |> assign(:head_title, "Tuist · Make mobile your competitive advantage")
    |> assign(
      :head_description,
      "The same iOS tooling that powers billion-user apps, delivered as a service for your team"
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/home.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign_structured_data(get_testimonials_structured_data(testimonials))
    |> assign(:testimonials, testimonials)
    |> assign(:read_more_posts, read_more_posts)
    |> render(:home, layout: false)
  end

  def about(conn, _params) do
    conn
    |> assign_structured_data(get_organization_structured_data())
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {gettext("Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {gettext("About"), Tuist.Environment.app_url(path: ~p"/about")}
      ])
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/generated/about.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(
      :head_description,
      "Learn more about Tuist, the open-source project that helps you scale your Swift development."
    )
    |> assign(:head_title, "About Tuist")
    |> render(:about, layout: false)
  end

  def support(conn, _params) do
    conn
    |> assign_structured_data(get_organization_structured_data())
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {gettext("Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {gettext("Support"), Tuist.Environment.app_url(path: ~p"/support")}
      ])
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/generated/support.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(
      :head_description,
      "Get help with Tuist. Access our support channels, documentation, and community resources."
    )
    |> assign(:head_title, "Support · Tuist")
    |> render(:support, layout: false)
  end

  def newsletter(conn, _params) do
    conn
    |> assign_structured_data(get_organization_structured_data())
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {gettext("Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {gettext("Swift Stories Newsletter"), Tuist.Environment.app_url(path: ~p"/newsletter")}
      ])
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/generated/swift-stories.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(
      :head_description,
      Newsletter.description()
    )
    |> render(:newsletter, layout: false)
  end

  def newsletter_issue(%{params: params} = conn, %{"issue_number" => issue_number}) do
    email_version? = Map.has_key?(params, "email")

    issue =
      with {issue_number, _} <- Integer.parse(issue_number),
           issue when not is_nil(issue) <-
             Enum.find(Newsletter.issues(), &(&1.number == issue_number)) do
        issue
      else
        :error ->
          raise NotFoundError,
                gettext("The newsletter issue number %{issue_number} is not a valid number.",
                  issue_number: issue_number
                )

        nil ->
          raise NotFoundError,
                gettext("The newsletter issue %{issue_number} was not found.",
                  issue_number: issue_number
                )
      end

    conn =
      conn
      |> put_layout(false)
      |> put_root_layout(false)

    conn =
      if email_version? do
        conn
        |> put_resp_header("Content-Type", "text/plain; charset=utf-8")
        |> PlugMinifyHtml.call(PlugMinifyHtml.init([]))
      else
        put_resp_header(conn, "Content-Type", "text/html")
      end

    render(conn, String.to_atom("newsletter_issue"), issue: issue, email_version?: email_version?)
  end

  def blog_rss(conn, _params) do
    posts = Blog.get_posts()
    last_build_date = posts |> List.last() |> Map.get(:date)

    conn
    |> assign(:posts, posts)
    |> assign(:last_build_date, last_build_date)
    |> render(:blog_rss, layout: false)
  end

  def blog_atom(conn, _params) do
    posts = Blog.get_posts()
    last_build_date = posts |> List.last() |> Map.get(:date)

    conn
    |> assign(:posts, posts)
    |> assign(:last_build_date, last_build_date)
    |> render(:blog_atom, layout: false)
  end

  def changelog_rss(conn, _params) do
    entries = Changelog.get_entries()
    last_build_date = entries |> List.last() |> Map.get(:date)

    conn
    |> assign(:entries, entries)
    |> assign(:last_build_date, last_build_date)
    |> render(:changelog_rss, layout: false)
  end

  def changelog_atom(conn, _params) do
    entries = Changelog.get_entries()
    last_build_date = entries |> List.last() |> Map.get(:date)

    conn
    |> assign(:entries, entries)
    |> assign(:last_build_date, last_build_date)
    |> render(:changelog_atom, layout: false)
  end

  def newsletter_rss(conn, _params) do
    issues = Newsletter.issues()
    last_build_date = issues |> List.last() |> Map.get(:date)

    conn
    |> assign(:issues, issues)
    |> assign(:last_build_date, last_build_date)
    |> render(:newsletter_rss, layout: false)
  end

  def newsletter_atom(conn, _params) do
    issues = Newsletter.issues()
    last_build_date = issues |> List.last() |> Map.get(:date)

    conn
    |> assign(:issues, issues)
    |> assign(:last_build_date, last_build_date)
    |> render(:newsletter_atom, layout: false)
  end

  def sitemap(conn, _params) do
    page_urls = Enum.map(Pages.get_pages(), &Tuist.Environment.app_url(path: &1.slug))

    post_urls = Enum.map(Blog.get_posts(), &Tuist.Environment.app_url(path: &1.slug))

    newsletter_issue_urls =
      Enum.map(
        Newsletter.issues(),
        &Tuist.Environment.app_url(path: ~p"/newsletter/issues/#{&1.number}")
      )

    entries =
      [
        Tuist.Environment.app_url(path: ~p"/"),
        Tuist.Environment.app_url(path: ~p"/pricing"),
        Tuist.Environment.app_url(path: ~p"/blog"),
        Tuist.Environment.app_url(path: ~p"/changelog")
      ] ++ page_urls ++ post_urls ++ newsletter_issue_urls

    conn
    |> assign(:entries, entries)
    |> render(:sitemap, layout: false)
  end

  def blog_post(%{request_path: request_path} = conn, _params) do
    request_path = Localization.path_without_locale(request_path)

    post = Enum.find(Blog.get_posts(), &(&1.slug == String.trim_trailing(request_path, "/")))

    if is_nil(post) do
      raise NotFoundError
    else
      related_posts = Enum.take_random(Blog.get_posts(), 3)
      author = Blog.get_authors()[post.author]

      conn
      |> assign(:head_title, post.title)
      |> assign(:head_description, post.excerpt)
      |> assign(:head_keywords, post.tags)
      |> assign(:head_fediverse_creator, author["fediverse_username"])
      |> assign(
        :head_image,
        if post.og_image_path do
          Tuist.Environment.app_url(
            path: post.og_image_path,
            marketing: true
          )
        else
          Tuist.Environment.app_url(
            path: "/marketing/images/og/generated#{post.slug}.jpg",
            marketing: true
          )
        end
      )
      |> assign(:head_twitter_card, "summary_large_image")
      |> assign_structured_data(get_blog_post_structured_markup_data(post))
      |> assign_structured_data(
        get_breadcrumbs_structured_data([
          {gettext("Tuist"), Tuist.Environment.app_url(path: ~p"/")},
          {gettext("Blog"), Tuist.Environment.app_url(path: ~p"/blog")},
          {post.title, Tuist.Environment.app_url(path: post.slug)}
        ])
      )
      |> assign(:post, post)
      |> assign(:author, author)
      |> assign(:related_posts, related_posts)
      |> render(:blog_post, layout: false)
    end
  end

  def pricing(conn, _params) do
    faqs = [
      {gettext("Why is your pricing model more accessible compared to traditional enterprise models?"),
       gettext(
         ~S"""
         <p>Our commitment to open-source and our core values shape our unique approach to pricing. Unlike many models that try to extract every dollar from you with "contact sales" calls, limited demos, and other sales tactics, we believe in fairness and transparency. We treat everyone equally and set prices that are fair for all. By choosing our services, you are not only getting a great product but also supporting the development of more open-source projects. We see building a thriving business as a long-term journey, not a short-term sprint filled with shady practices. You can %{read_more}  about our philosophy.</p>
         <p>By supporting Tuist, you are also supporting the development of more open-source software for the Swift ecosystem.</p>
         """,
         read_more: "<a href=\"#{~p"/blog/2024/11/05/our-pricing-philosophy"}\">#{gettext("read more")}</a>"
       )},
      {gettext("How can I estimate the cost of my project?"),
       gettext(
         "You can set up the Air plan, and use the features for a few days to get a usage estimate. If you need a higher limit, let us know and we can help you set up a custom plan."
       )},
      {gettext("Is there a free trial on paid plans?"),
       gettext("We have a generous free tier on every paid plan so you can try out the features before paying any money.")},
      {gettext("Do you offer discounts for non-profits and open-source?"),
       gettext("Yes, we do. Please reach out to oss@tuist.io for more information.")}
    ]

    plans = Tuist.Billing.get_plans()

    conn
    |> assign(:head_title, "Pricing · Plans for every developer · Tuist")
    |> assign(:faqs, faqs)
    |> assign(:plans, plans)
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/pricing.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign_structured_data(get_faq_structured_data(faqs))
    |> assign_structured_data(get_pricing_plans_structured_data(plans))
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {gettext("Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {gettext("Pricing"), Tuist.Environment.app_url(path: ~p"/pricing")}
      ])
    )
    |> assign(
      :head_description,
      gettext(
        "Discover our flexible pricing plans at Tuist. Enjoy a free tier with no time limits, and pay only for what you use. Plus, it's free forever for open source projects."
      )
    )
    |> render(:pricing, layout: false)
  end

  def page(conn, _params) do
    request_path = Localization.path_without_locale(conn.request_path)

    page = Enum.find(Pages.get_pages(), &(&1.slug == String.trim_trailing(request_path, "/")))

    conn
    |> assign(:head_title, "#{page.title}")
    |> assign(:head_description, page.excerpt)
    |> assign(
      :head_image,
      Tuist.Environment.app_url(
        path: "/marketing/images/og/generated/#{page.slug |> String.split("/") |> List.last()}.jpg"
      )
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {gettext("Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {page.title, Tuist.Environment.app_url(path: page.slug)}
      ])
    )
    |> assign(:page, page)
    |> render(:page, layout: false)
  end

  defp home_testimonials do
    [
      [
        %{
          author: "Garnik Harutyunyan",
          author_title: "Senior iOS developer at FREENOW",
          author_link: "https://www.linkedin.com/in/garnikh/",
          avatar_src: "/marketing/images/testimonials/garnik.jpeg",
          body:
            gettext(~s"""
            <p>Tuist has been a game-changer for our large codebase, where multiple engineers collaborate simultaneously. It helps us avoid conflicts in project organization and provides full control over project configuration, allowing us to customize everything to our needs. For a modularized app, Tuist is the perfect ally—its ability to effortlessly reuse configurations across modules has significantly streamlined our development process.</p>
            <p>Additionally, the way Tuist manages package dependencies is outstanding. As soon as you open Xcode, you're ready to jump right into coding without waiting for 30+ packages to resolve every time. It's truly a productivity booster.</p>
            <p>I've been using it since version 1, and it's been incredible to see how the product has evolved and expanded with new features over time. Their effort in resolving underlying issues and evolving the product has made Tuist a mature, reliable tool that we can depend on.</p>
            """)
        },
        %{
          author: "Kai Oelfke",
          author_title: "Indie developer",
          author_link: "https://www.kaioelfke.de",
          avatar_src: "/marketing/images/testimonials/kai.jpeg",
          body:
            gettext(~S"""
            <p>With macros, external SDKs, and many SPM modules (fully modularized app) Xcode was constantly slow or stuck on my M1 device. SPM kept resolving, code completion didn’t work, and <a href="https://github.com/swiftlang/swift-syntax" target="_blank">swift-syntax</a> compiled forever. All this changed with Tuist. It’s not just for big teams with big apps. Tuist gave me back my productivity as indie developer for my side projects.</p>
            """)
        }
      ],
      [
        %{
          author: "Shahzad Majeed",
          author_title: "Senior Lead Software Engineer - Architecture/Platform, DraftKings, Inc.",
          author_link: "https://www.linkedin.com/in/shahzadmajeed",
          avatar_src: "/marketing/images/testimonials/shahzad.jpeg",
          body:
            gettext(~S"""
            <p>Tuist has revolutionized our iOS development workflow at DraftKings. Its automation capabilities have streamlined project generation, build settings, and dependency management. With modularization, we maximize code sharing across apps, reducing duplication. Code generation allows us to quickly bootstrap new products that seamlessly integrate with existing ones through centralized dependency management. The build caching feature can significantly improve build times, both locally and in CI/CD environment. Tuist is an indispensable set of developer tools, greatly enhancing productivity and efficiency. Highly recommended for iOS teams seeking workflow optimization.</p>
            """)
        },
        %{
          author: "Cedric Gatay",
          author_title: "iOS Lead Dev (Contractor) at Chanel",
          author_link: "https://github.com/CedricGatay",
          avatar_src: "/marketing/images/testimonials/cedric.jpeg",
          body:
            gettext(
              "Tuist has allowed us to migrate our existing monolythic codebase to a modular one. We extracted our different domains into specific modules. It allowed us to remove extra dependencies, ease testability and made our development cycles faster than ever. It even allowed us to bring up “Test Apps” for speeding up our development on each module. Tuist is a game changer in iOS project life."
            )
        },
        %{
          author: "Yousef Moahmed",
          author_title: "Senior iOS Dev at Bazargate",
          author_link: "https://www.linkedin.com/in/joeoct91/",
          avatar_src: "/marketing/images/testimonials/yousef.jpeg",
          body:
            gettext(
              "Using Tuist in our current project has been a game-changer. It has significantly de-stressed our build times and reduced conflicts within the team, allowing us to focus more on development and less on configuration issues. Tuist has seamlessly integrated into our workflow and has proven to be an essential tool in our pipeline. We’re confident that it will continue to enhance our productivity and collaboration in future projects."
            )
        }
      ],
      [
        %{
          author: "Alberto Salas",
          author_title: "Senior iOS Engineer at Back Market",
          author_link: "https://www.linkedin.com/in/albsala",
          avatar_src: "/marketing/images/testimonials/alberto.jpeg",
          body:
            gettext(
              "Since adopting Tuist in our iOS project, we’ve seen major improvements in scalability and productivity. It simplifies module management, allowing us to apply consistent rules and configurations across the project, strengthening our modularization strategy. Its flexibility lets us easily customize the project to fit our needs. For instance, we can use dynamic frameworks during development and static frameworks in other environments, giving us better control. Tuist has also improved build times, boosted Xcode performance, and eliminated merge conflicts by not tracking Xcode project files in Git. Overall, it has made our development process faster and more efficient, allowing the team to focus on building features without being slowed down by tool limitations."
            )
        },
        %{
          author: "Alon Zilbershtein",
          author_title: "Staff Software Engineer at Chegg",
          author_link: "https://www.linkedin.com/in/alonzilber",
          avatar_src: "/marketing/images/testimonials/alon.jpeg",
          body:
            "It made a the transition to SPM and the migration of our private pods to our monorepo super easy. We were able to create a framework template, making option to build a modular project very simple. After integrating Tuist, we reduced our build time by 30%! We have no more project file conflicts and honestly - once you try it, you’ll never go back."
        }
      ]
    ]
  end

  def assign_default_head_tags(conn, _params) do
    conn
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(:head_include_blog_rss_and_atom, true)
    |> assign(:head_include_changelog_rss_and_atom, true)
    |> assign(:head_include_newsletter_rss_and_atom, true)
  end

  defp put_resp_header_cache_control(conn, _opts) do
    put_resp_header(conn, "cache-control", "public, max-age=86400, immutable")
  end

  defp put_resp_header_server(conn, _opts) do
    put_resp_header(conn, "server", "Bandit")
  end
end
