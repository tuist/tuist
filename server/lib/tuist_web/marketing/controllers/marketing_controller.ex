defmodule TuistWeb.Marketing.MarketingController do
  use TuistWeb, :controller
  use Noora

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

    conn
    |> assign(:head_title, "Tuist · A virtual platform team for mobile devs who ship")
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/home.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(:read_more_posts, read_more_posts)
    |> render(:home, layout: false)
  end

  def home(conn, _params) do
    conn
    |> assign(:head_title, "Tuist")
    |> assign(
      :head_description,
      dgettext(
        "marketing",
        "The same iOS tooling that powers billion-user apps, delivered as a service for your team"
      )
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/home.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> render(:home, layout: false)
  end

  def about(conn, _params) do
    conn
    |> assign_structured_data(get_organization_structured_data())
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {dgettext("marketing", "About"), Tuist.Environment.app_url(path: ~p"/about")}
      ])
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/about.jpg")
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
        {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {dgettext("marketing", "Support"), Tuist.Environment.app_url(path: ~p"/support")}
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
        {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {dgettext("marketing", "Swift Stories Newsletter"),
         Tuist.Environment.app_url(path: ~p"/newsletter")}
      ])
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/generated/tuist-digest.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(:head_title, dgettext("marketing", "Tuist Digest Newsletter"))
    |> assign(
      :head_description,
      Newsletter.description()
    )
    |> render(:newsletter, layout: false)
  end

  def newsletter_signup(conn, %{"email" => email}) do
    # Create a verification token (simple base64 encoded email)
    verification_token = Base.encode64(email)
    verification_url = url(conn, ~p"/newsletter/verify?token=#{verification_token}")

    case Tuist.Loops.send_newsletter_confirmation(email, verification_url) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> json(%{
          success: true,
          message: dgettext("marketing", "Please check your email to confirm your subscription.")
        })

      {:error, _reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> put_status(400)
        |> json(%{
          success: false,
          message: dgettext("marketing", "Something went wrong. Please try again.")
        })
    end
  end

  def newsletter_verify(conn, %{"token" => token} = _params) do
    case Base.decode64(token) do
      {:ok, email} ->
        case Tuist.Loops.add_to_newsletter_list(email) do
          :ok ->
            conn
            |> assign(:head_title, dgettext("marketing", "Successfully Subscribed!"))
            |> assign(
              :head_image,
              Tuist.Environment.app_url(path: "/marketing/images/og/generated/tuist-digest.jpg")
            )
            |> assign(:head_twitter_card, "summary_large_image")
            |> assign(:email, email)
            |> assign(:error_message, nil)
            |> render(:newsletter_verify, layout: false)

          {:error, _reason} ->
            conn
            |> assign(:head_title, "Newsletter Verification Failed")
            |> assign(
              :head_image,
              Tuist.Environment.app_url(path: "/marketing/images/og/generated/tuist-digest.jpg")
            )
            |> assign(:head_twitter_card, "summary_large_image")
            |> assign(
              :error_message,
              dgettext("marketing", "Verification failed. Please try signing up again.")
            )
            |> assign(:email, nil)
            |> render(:newsletter_verify, layout: false)
        end

      :error ->
        conn
        |> assign(:head_title, dgettext("marketing", "Newsletter Verification Failed"))
        |> assign(
          :head_image,
          Tuist.Environment.app_url(path: "/marketing/images/og/generated/tuist-digest.jpg")
        )
        |> assign(:head_twitter_card, "summary_large_image")
        |> assign(
          :error_message,
          dgettext("marketing", "Invalid verification link. Please try signing up again.")
        )
        |> assign(:email, nil)
        |> render(:newsletter_verify, layout: false)
    end
  end

  def newsletter_verify(conn, _params) do
    conn
    |> assign(:head_title, dgettext("marketing", "Newsletter Verification Failed"))
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: "/marketing/images/og/generated/tuist-digest.jpg")
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign(
      :error_message,
      dgettext("marketing", "Verification link expired or invalid. Please try signing up again.")
    )
    |> assign(:email, nil)
    |> render(:newsletter_verify, layout: false)
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
                dgettext(
                  "marketing",
                  "The newsletter issue number %{issue_number} is not a valid number.",
                  issue_number: issue_number
                )

        nil ->
          raise NotFoundError,
                dgettext("marketing", "The newsletter issue %{issue_number} was not found.",
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

      processed_content = Blog.process_content(post.body)

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
          {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
          {dgettext("marketing", "Blog"), Tuist.Environment.app_url(path: ~p"/blog")},
          {post.title, Tuist.Environment.app_url(path: post.slug)}
        ])
      )
      |> assign(:post, post)
      |> assign(:author, author)
      |> assign(:related_posts, related_posts)
      |> assign(:processed_content, processed_content)
      |> render(:blog_post, layout: false)
    end
  end

  def blog_post_iframe(conn, _params) do
    conn |> render(:blog_post, layout: false)
  end

  def pricing(conn, _params) do
    faqs = [
      {dgettext(
         "marketing",
         "Why is your pricing model more accessible compared to traditional enterprise models?"
       ),
       dgettext(
         "marketing",
         ~S"""
         <p>Our commitment to open-source and our core values shape our unique approach to pricing. Unlike many models that try to extract every dollar from you with "contact sales" calls, limited demos, and other sales tactics, we believe in fairness and transparency. We treat everyone equally and set prices that are fair for all. By choosing our services, you are not only getting a great product but also supporting the development of more open-source projects. We see building a thriving business as a long-term journey, not a short-term sprint filled with shady practices. You can %{read_more}  about our philosophy.</p>
         <p>By supporting Tuist, you are also supporting the development of more open-source software for the Swift ecosystem.</p>
         """,
         read_more:
           "<a href=\"#{~p"/blog/2024/11/05/our-pricing-philosophy"}\">#{dgettext("marketing", "read more")}</a>"
       )},
      {dgettext("marketing", "How can I estimate the cost of my project?"),
       dgettext(
         "marketing",
         "You can set up the Air plan, and use the features for a few days to get a usage estimate. If you need a higher limit, let us know and we can help you set up a custom plan."
       )},
      {dgettext("marketing", "Is there a free trial on paid plans?"),
       dgettext(
         "marketing",
         "We have a generous free tier on every paid plan so you can try out the features before paying any money."
       )},
      {dgettext("marketing", "Do you offer discounts for non-profits and open-source?"),
       dgettext("marketing", "Yes, we do. Please reach out to oss@tuist.io for more information.")}
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
        {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {dgettext("marketing", "Pricing"), Tuist.Environment.app_url(path: ~p"/pricing")}
      ])
    )
    |> assign(
      :head_description,
      dgettext(
        "marketing",
        "Discover our flexible pricing plans at Tuist. Enjoy a free tier with no time limits, and pay only for what you use. Plus, it's free forever for open source projects."
      )
    )
    |> render(:pricing, layout: false)
  end

  def page(conn, _params) do
    request_path = Localization.path_without_locale(conn.request_path)

    page = Enum.find(Pages.get_pages(), &(&1.slug == String.trim_trailing(request_path, "/")))

    head_title = page.head_title || "#{page.title} · Tuist"
    head_description = page.head_description || page.excerpt

    conn
    |> assign(:head_title, head_title)
    |> assign(:head_description, head_description)
    |> assign(
      :head_image,
      Tuist.Environment.app_url(
        path: "/marketing/images/og/#{page.slug |> String.split("/") |> List.last()}.jpg"
      )
    )
    |> assign(:head_twitter_card, "summary_large_image")
    |> assign_structured_data(
      get_breadcrumbs_structured_data([
        {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
        {page.title, Tuist.Environment.app_url(path: page.slug)}
      ])
    )
    |> assign(:page, page)
    |> render(:page, layout: false)
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
  end

  defp put_resp_header_cache_control(conn, _opts) do
    put_resp_header(conn, "cache-control", "public, max-age=86400, immutable")
  end

  defp put_resp_header_server(conn, _opts) do
    put_resp_header(conn, "server", "Bandit")
  end
end
