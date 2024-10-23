defmodule TuistWeb.MarketingController do
  use TuistWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:testimonials, home_testimonials())
    |> render(:home, layout: false)
  end

  def about(conn, _params) do
    conn
    |> render(:about, layout: false)
  end

  def blog(conn, _params) do
    conn
    |> render(:blog, layout: false)
  end

  def pricing(conn, _params) do
    conn
    |> render(:pricing, layout: false)
  end

  def changelog(conn, _params) do
    conn
    |> render(:changelog, layout: false)
  end

  def terms(conn, _params) do
    conn
    |> render(:terms, layout: false)
  end

  def cookies(conn, _params) do
    conn
    |> render(:cookies, layout: false)
  end

  def privacy(conn, _params) do
    conn
    |> render(:privacy, layout: false)
  end

  defp home_testimonials() do
    [
      [
        %{
          author: "Garnik Harutyunyan",
          author_title: "Senior iOS developer at FreeNow",
          author_link: "https://www.linkedin.com/in/garnikh/",
          avatar_src: "/marketing/testimonials/garnik.jpeg",
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
          avatar_src: "/marketing/testimonials/kai.jpeg",
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
          avatar_src: "/marketing/testimonials/shahzad.jpeg",
          body:
            gettext(~S"""
            <p>Tuist has revolutionized our iOS development workflow at DraftKings. Its automation capabilities have streamlined project generation, build settings, and dependency management. With modularization, we maximize code sharing across apps, reducing duplication. Code generation allows us to quickly bootstrap new products that seamlessly integrate with existing ones through centralized dependency management. The build caching feature can significantly improve build times, both locally and in CI/CD environment. Tuist is an indispensable set of developer tools, greatly enhancing productivity and efficiency. Highly recommended for iOS teams seeking workflow optimization.</p>
            """)
        },
        %{
          author: "Cedric Gatay",
          author_title: "iOS Lead Dev (Contractor) at Chanel",
          author_link: "https://github.com/CedricGatay",
          avatar_src: "/marketing/testimonials/cedric.jpeg",
          body:
            gettext(
              "Tuist has allowed us to migrate our existing monolythic codebase to a modular one. We extracted our different domains into specific modules. It allowed us to remove extra dependencies, ease testability and made our development cycles faster than ever. It even allowed us to bring up “Test Apps” for speeding up our development on each module. Tuist is a game changer in iOS project life."
            )
        },
        %{
          author: "Yousef Moahmed",
          author_title: "Senior iOS Dev at Bazargate",
          author_link: "https://www.linkedin.com/in/joeoct91/",
          avatar_src: "/marketing/testimonials/yousef.jpeg",
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
          avatar_src: "/marketing/testimonials/alberto.jpeg",
          body:
            gettext(
              "Since adopting Tuist in our iOS project, we’ve seen major improvements in scalability and productivity. It simplifies module management, allowing us to apply consistent rules and configurations across the project, strengthening our modularization strategy. Its flexibility lets us easily customize the project to fit our needs. For instance, we can use dynamic frameworks during development and static frameworks in other environments, giving us better control. Tuist has also improved build times, boosted Xcode performance, and eliminated merge conflicts by not tracking Xcode project files in Git. Overall, it has made our development process faster and more efficient, allowing the team to focus on building features without being slowed down by tool limitations."
            )
        },
        %{
          author: "Martha Alans",
          author_title: "Staff Software Engineer at Guinda",
          author_link: "",
          avatar_src:
            "https://img.freepik.com/premium-vector/cute-avatar-akita-head-simple-cartoon-vector-illustration-dog-breeds-nature-concept-icon-isolated_772770-320.jpg",
          body: "Tellus faucibus tellus sem proin vitae pellentesque. Sed turpis enim odio."
        },
        %{
          author: "Marc Marín",
          author_title: "Product designer at Google",
          author_link: "",
          avatar_src:
            "https://img.freepik.com/premium-vector/cute-avatar-akita-head-simple-cartoon-vector-illustration-dog-breeds-nature-concept-icon-isolated_772770-320.jpg",
          body: "Amet porta posuere nunc mi. Proin"
        }
      ]
    ]
  end
end
