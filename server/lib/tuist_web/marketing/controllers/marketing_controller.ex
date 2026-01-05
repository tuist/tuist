defmodule TuistWeb.Marketing.MarketingController do
  use TuistWeb, :controller
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Changelog
  alias Tuist.Marketing.Content
  alias Tuist.Marketing.Customers
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
    locale = Gettext.get_locale(TuistWeb.Gettext)

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
    |> assign(:featured_testimonials, get_featured_testimonials(locale))
    |> assign(:testimonial_columns, get_testimonial_columns(locale))
    |> render(:home, layout: false)
  end

  defp get_featured_testimonials("ko") do
    %{
      quote_line_one: "Tuist를 적용했을 뿐인데 빌드 속도가 25% 단축되었어요!",
      quote_line_two: "한국 iOS 개발자들에게 정말 인기 있는 도구 입니다",
      author_name: "이영준 (Youngjun Lee), 게임도우미",
      author_avatar: "https://www.gravatar.com/avatar/placeholder"
    }
  end

  defp get_featured_testimonials("ru") do
    get_english_featured_testimonials()
  end

  defp get_featured_testimonials(_locale) do
    get_english_featured_testimonials()
  end

  defp get_testimonial_columns("ko") do
    english_columns = get_english_testimonial_columns()

    [
      [
        %{
          quote:
            "Tuist는 iOS 개발자들에게 정말 멋진 도구에요. 이걸 적용한 후 더 이상 Xcode 프로젝트에서 Conflicts를 경험하지 않게 되었어요. 게다가, 빌드에 걸리는 시간도 줄여줘서 더 중요한 일에 시간을 사용할 수 있게 되었어요. 그리고 고맙게도, Tuist는 한국의 SNS에서도 피드백을 받고 있어서 문제가 있다면 언제든 도와줄 겁니다.",
          name: "이영준 (Youngjun Lee)",
          role: "CEO of 게임도우미",
          avatar_src: "/marketing/images/testimonials/youngjun-lee.jpeg",
          highlighted: true,
          logo_svg: """
          <!-- TODO: Add company logo SVG here if needed -->
          """
        },
        %{
          quote:
            "Tuist를 도입한 이후 의존성 관리와 외부 라이브러리 업데이트가 훨씬 간결해졌습니다. Project.swift로 프로젝트 구조와 의존성을 정의하다 보니 구성 검토와 리팩터링이 수월해졌고, 모듈 단위로 테스트를 분리할 수 있어 TDD에 최적화되었습니다. 캐시 기능 덕분에 클린 빌드와 증분 빌드 시간이 크게 줄어 개발 루프가 빨라졌고, 스캐폴딩 기능으로 신규 기능 파일을 손쉽게 생성할 수 있어 반복 작업이 줄었습니다. 또한 .pbxproj 충돌을 없애 병합 과정이 깔끔해진 점도 만족스러웠습니다. 빠르게 변화하는 iOS 환경에 맞추어 Tuist 또한 빠른 업데이트 속도가 제일 좋았습니다.",
          name: "Akaps",
          role: "iOS Developer at HSociety",
          avatar_src: "/marketing/images/testimonials/akaps.jpeg",
          highlighted: false,
          logo_svg: nil
        },
        %{
          quote:
            "Tuist는 비누랩스의 iOS 개발 워크플로우를 획기적으로 개선했습니다. 프로젝트 파일을 코드로 관리하고 자동 생성하는 방식 덕분에 팀원 간 pbxproj 파일 충돌이 완전히 사라졌고, Git 머지가 훨씬 수월해졌습니다. 특히 Tuist Cache를 활용해 의존성을 사전 빌드함으로써 개발 환경의 빌드 시간을 대폭 단축할 수 있었습니다. Swift Macro 모듈을 도입할 때도 바이너리 캐싱 기능 덕분에 매번 매크로를 재컴파일할 필요 없이 빠르게 개발할 수 있었습니다. 변경되지 않은 모듈은 캐시된 바이너리로 대체하고 작업 중인 모듈만 소스로 빌드하는 방식으로, 대규모 모듈화 프로젝트에서도 빠른 피드백 루프를 유지하며 팀 전체의 생산성을 크게 높일 수 있었습니다.",
          name: "김인환 (Inhwan Kim)",
          role: "iOS Developer at 비누랩스",
          avatar_src: "/marketing/images/testimonials/inhwan-kim.jpg",
          highlighted: false,
          logo_svg: nil
        }
      ],
      Enum.at(english_columns, 1),
      Enum.at(english_columns, 2)
    ]
  end

  defp get_testimonial_columns("ru") do
    get_english_testimonial_columns()
  end

  defp get_testimonial_columns(_locale) do
    get_english_testimonial_columns()
  end

  defp get_english_featured_testimonials do
    %{
      quote_line_one:
        dgettext(
          "marketing",
          "\"We could solve our immediate problems and do so while maintaining a familiar"
        ),
      quote_line_two: dgettext("marketing", "core development experience\""),
      author_name: dgettext("marketing", "Jonathan Crooke, Bumble"),
      author_avatar: "https://www.gravatar.com/avatar/292c129cf17a552c08b4d9dcf2c6c1f8"
    }
  end

  defp get_english_testimonial_columns do
    [
      # Column 1
      [
        %{
          quote:
            dgettext(
              "marketing",
              "Since adopting Tuist in our iOS project, we've seen major improvements in scalability and productivity. Overall, it has made our development process faster and more efficient, allowing the team to focus on building features without being slowed down by tool limitations."
            ),
          name: "Alon Zilbershtein",
          role: "Staff Software Engineer at Chegg",
          avatar_src: "/marketing/images/home/testimonials/alon.jpeg",
          highlighted: true,
          logo_svg: """
          <svg width="151" height="61" viewBox="0 0 151 61" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_734_2101)"><path d="M56.75 16.8892C54.6396 14.815 51.601 13.6435 47.6847 13.9661C45.6158 14.137 43.6207 15.274 42.8187 16.1977V2.41602L34.7393 3.91211V44.1396H42.8259V29.2574C42.6691 23.323 44.7633 21.8941 47.9136 21.8941C50.9973 21.8941 52.7004 24.1085 52.7004 28.8579V44.1127H60.45V27.431C60.4518 22.5356 59.111 19.2092 56.75 16.8892ZM21.4964 36.6839C23.7005 36.5764 25.8362 35.8345 27.6763 34.5369L29.0478 33.5766L32.5911 40.0488L31.3962 40.9246C28.1418 43.3077 24.2845 44.5803 20.3358 44.5736C17.2675 44.5714 14.2427 43.8014 11.5047 42.326C8.76663 40.8505 6.39191 38.7106 4.57166 36.0785C2.7514 33.4465 1.53647 30.3957 1.02463 27.1719C0.512799 23.9481 0.718369 20.6413 1.6248 17.5177C2.53122 14.3939 4.11319 11.5407 6.24335 9.18747C8.37352 6.83428 10.9924 5.04689 13.8891 3.96918C16.7859 2.89147 19.8796 2.55354 22.9214 2.9826C25.963 3.41166 28.8677 4.59572 31.4016 6.43948L32.5911 7.3114L29.0478 13.7952L27.6763 12.8348C25.8362 11.5373 23.7005 10.7953 21.4964 10.6879C19.2922 10.5804 17.1019 11.1113 15.1583 12.2244C13.2147 13.3374 11.5904 14.9909 10.4582 17.0091C9.32592 19.0272 8.72807 21.3346 8.72807 23.6859C8.72807 26.0371 9.32592 28.3446 10.4582 30.3627C11.5904 32.3808 13.2147 34.0343 15.1583 35.1474C17.1019 36.2604 19.2922 36.7914 21.4964 36.6839ZM140.905 16.0998L140.862 16.3112L140.707 16.1728C138.905 14.5827 136.553 13.8106 133.52 13.8106C125.925 13.8106 119.747 20.5977 119.747 28.9406C119.747 37.2834 125.925 44.0705 133.52 44.0705C135.408 44.078 137.274 43.6543 138.996 42.8279L139.253 42.705L139.163 42.9893C138.203 46.0045 135.627 47.95 132.435 48.0594H132.046C130.215 48.1094 128.434 47.4144 127.066 46.1159L126.706 45.7855L122.301 51.1131L122.618 51.4473C125.421 54.403 129.667 55.7473 132.426 55.7473C141.064 55.7473 147.334 49.085 147.334 39.9049V13.8874H141.346L140.905 16.0998ZM134.149 36.1695C130.629 36.1695 127.768 32.9237 127.768 28.9348C127.768 24.9458 130.629 21.7002 134.149 21.7002C137.669 21.7002 140.532 24.9458 140.532 28.9348C140.532 32.9237 137.671 36.1695 134.149 36.1695ZM111.809 16.0999L111.763 16.3207L111.6 16.1767C109.797 14.5884 107.454 13.8164 104.418 13.8164C96.8246 13.8164 90.6483 20.6017 90.6483 28.9406C90.6483 37.2795 96.8246 44.0648 104.418 44.0648C106.303 44.0719 108.169 43.6489 109.889 42.8241L110.159 42.6935L110.065 42.9912C109.111 46.0141 106.535 47.9615 103.345 48.0729H102.958C101.124 48.1238 99.3418 47.4281 97.9725 46.1274L97.6214 45.8009L93.2234 51.1209L93.537 51.4512C96.3382 54.4049 100.582 55.7493 103.342 55.7493C111.976 55.7493 118.243 49.0889 118.243 39.9126V13.8932H112.25L111.809 16.0999ZM105.055 36.1752C101.532 36.1752 98.6662 32.9276 98.6662 28.9348C98.6662 24.9421 101.532 21.6944 105.055 21.6944C108.579 21.6944 111.444 24.9421 111.444 28.9348C111.444 32.9276 108.579 36.1752 105.055 36.1752ZM61.991 29.2305C61.991 20.5305 67.9546 13.7164 75.5673 13.7164C83.1497 13.7164 89.0858 20.5305 89.0858 29.2286C89.0827 30.3371 89.0123 31.4443 88.8771 32.5434H70.1155L70.1966 32.8354C70.5766 34.1657 71.3828 35.3117 72.4746 36.0734C73.5406 36.8311 74.7779 37.2701 76.0574 37.3448C78.9534 37.5138 81.1384 36.638 82.9057 34.585L87.7017 38.1091C87.0581 39.175 83.3045 44.7446 76.0647 44.7446C68.2988 44.7446 61.991 37.7845 61.991 29.2305ZM69.4252 26.6877L69.4018 26.9374H82.2699L82.2574 26.6973C82.0408 22.4932 78.7446 20.2252 75.7547 20.2252C74.2063 20.2418 72.7199 20.8756 71.5879 22.0017C70.3472 23.2242 69.5765 24.8941 69.4252 26.6877Z" fill="currentColor"/></g><defs><clipPath id="clip0_734_2101"><rect width="157.5" height="60" fill="white" transform="translate(0.75 0.75)"/></clipPath></defs></svg>
          """
        },
        %{
          quote:
            dgettext(
              "marketing",
              "Tuist has been a game-changer for our large codebase, where multiple engineers collaborate simultaneously. I've been using it since version 1, and it's been incredible to see how the product has evolved and expanded with new features over time."
            ),
          name: "Garnik Harutyunyan",
          role: "Senior iOS developer at FREENOW",
          avatar_src: "/marketing/images/home/testimonials/garnik.jpeg",
          highlighted: false,
          logo_svg: nil
        }
      ],
      # Column 2
      [
        %{
          quote:
            dgettext(
              "marketing",
              "Tuist has revolutionized our iOS development workflow at DraftKings. Its automation capabilities have streamlined project generation, build settings, and dependency management. Highly recommended for iOS teams seeking workflow optimization."
            ),
          name: "Shahzad Majeed",
          role: "Sr Lead Software Engineer at DraftKings",
          avatar_src: "/marketing/images/home/testimonials/shahzad.jpeg",
          highlighted: false,
          logo_svg: nil
        },
        %{
          quote:
            dgettext(
              "marketing",
              "Since adopting Tuist in our iOS project, we've seen major improvements in scalability and productivity. Overall, it has made our development process faster and more efficient, allowing the team to focus on building features without being slowed down by tool limitations."
            ),
          name: "Alberto Salas",
          role: "Senior iOS Engineer at Back Market",
          avatar_src: "/marketing/images/home/testimonials/alberto.jpeg",
          highlighted: false,
          logo_svg: nil
        },
        %{
          quote:
            dgettext(
              "marketing",
              "Using Tuist in our current project has been a game-changer. It has significantly de-stressed our build times and reduced conflicts within the team, allowing us to focus more on development and less on configuration issues. We're confident that it will continue to enhance our productivity and collaboration in future projects."
            ),
          name: "Yousef Moahmed",
          role: "Senior iOS Dev at Bazargate",
          avatar_src: "/marketing/images/home/testimonials/yousef.jpeg",
          highlighted: false,
          logo_svg: nil
        }
      ],
      # Column 3
      [
        %{
          quote:
            dgettext(
              "marketing",
              "With macros, external SDKs, and many SPM modules (fully modularized app) Xcode was constantly slow or stuck on my M1 device. SPM kept resolving, code completion didn't work, and swift-syntax compiled forever. It's not just for big teams with big apps. Tuist gave me back my productivity as indie developer for my side projects."
            ),
          name: "Kai Oelfke",
          role: "Indie developer",
          avatar_src: "/marketing/images/home/testimonials/kai.jpeg",
          highlighted: false,
          logo_svg: nil
        },
        %{
          quote:
            dgettext(
              "marketing",
              "Tuist has allowed us to migrate our existing monolythic codebase to a modular one. We extracted our different domains into specific modules. It allowed us to remove extra dependencies, ease testability and made our development cycles faster than ever. It even allowed us to bring up 'Test Apps' for speeding up our development on each module."
            ),
          name: "Cedric Gatay",
          role: "iOS Lead Dev (Contractor) at Chanel",
          avatar_src: "/marketing/images/home/testimonials/cedric.jpeg",
          highlighted: true,
          logo_svg: """
          <svg width="239" height="38" viewBox="0 0 239 38" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" clip-rule="evenodd" d="M34.3888 27.7049C34.3596 27.7619 34.3027 27.876 34.2748 27.9622C31.1929 33.7839 25.1417 37.75 18.2356 37.75C8.21849 37.75 0 29.3593 0 19C0 8.69785 8.21849 0.25 18.2356 0.25C25.1709 0.25 31.2499 4.30229 34.3027 10.2102C34.3888 10.3242 34.4166 10.3813 34.5028 10.5523C34.532 10.5815 28.681 14.8046 28.624 14.7198C28.5949 14.6058 28.567 14.5196 28.51 14.4626C26.8253 10.2672 22.8313 7.47038 18.2356 7.55658C12.0996 7.61358 7.04804 12.693 7.04804 19C7.04804 25.364 12.0996 30.5019 18.2356 30.5019C22.6881 30.5019 26.5694 27.7619 28.3376 23.8807C28.4238 23.7376 28.453 23.6236 28.51 23.5096L34.3888 27.7049Z" fill="currentColor"/><path fill-rule="evenodd" clip-rule="evenodd" d="M41.9509 0.59375H48.9711V13.6929H67.4082V0.59375H74.4854V37.0372H67.4082V21.0272H48.9711V37.0372H41.9509V0.59375Z" fill="currentColor"/><path fill-rule="evenodd" clip-rule="evenodd" d="M173.573 37.0372V0.59375H199.058V7.95584H180.679V15.2331H197.66V22.5105H180.679V29.7877H201.655V37.0372H173.573Z" fill="currentColor"/><path fill-rule="evenodd" clip-rule="evenodd" d="M211.614 37.0372V0.59375H218.749V29.7877H238.555V37.0372H211.614Z" fill="currentColor"/><path fill-rule="evenodd" clip-rule="evenodd" d="M135.273 37.0372H135.044H128.138V0.59375H128.651H138.04L153.651 22.5105V0.59375H160.729V37.0372H155.078L135.273 9.55441V37.0372Z" fill="currentColor"/><path fill-rule="evenodd" clip-rule="evenodd" d="M101.283 7.95584L95.0622 22.5105H107.79L101.283 7.95584ZM91.865 29.7877L88.612 37.0372H80.1643L96.3175 0.59375H106.192L122.459 37.0372H114.011L110.73 29.7877H91.865Z" fill="currentColor"/></svg>
          """
        }
      ]
    ]
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
      Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/about.jpg"))
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
      Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/support.jpg"))
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
        {dgettext("marketing", "Swift Stories Newsletter"), Tuist.Environment.app_url(path: ~p"/newsletter")}
      ])
    )
    |> assign(
      :head_image,
      Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/tuist-digest.jpg"))
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
    email = String.trim(email)

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
              Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/tuist-digest.jpg"))
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
              Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/tuist-digest.jpg"))
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
          Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/tuist-digest.jpg"))
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
      Tuist.Environment.app_url(path: og_image_path("/marketing/images/og/generated/tuist-digest.jpg"))
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
                dgettext("marketing", "The newsletter issue %{issue_number} was not found.", issue_number: issue_number)
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
    entries = blog_entries()
    last_build_date = entries |> List.last() |> Content.get_entry_date()

    conn
    |> assign(:entries, entries)
    |> assign(:last_build_date, last_build_date)
    |> render(:blog_rss, layout: false)
  end

  def blog_atom(conn, _params) do
    entries = blog_entries()
    last_build_date = entries |> List.last() |> Content.get_entry_date()

    conn
    |> assign(:entries, entries)
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

    base_paths = [~p"/", ~p"/pricing", ~p"/blog", ~p"/changelog", ~p"/customers"]

    # Generate URLs for all locales
    localized_entries =
      for locale <- Localization.all_locales(),
          path <- base_paths do
        localized_path = Localization.localized_href(path, locale)
        Tuist.Environment.app_url(path: localized_path)
      end

    entries = localized_entries ++ page_urls ++ post_urls ++ newsletter_issue_urls

    conn
    |> assign(:entries, entries)
    |> render(:sitemap, layout: false)
  end

  defp blog_entries do
    Content.get_entries()
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

  def case_study(%{request_path: request_path} = conn, _params) do
    request_path = Localization.path_without_locale(request_path)

    case_study =
      Enum.find(Customers.get_case_studies(), &(&1.slug == String.trim_trailing(request_path, "/")))

    if is_nil(case_study) do
      raise NotFoundError
    else
      related_case_studies =
        Customers.get_case_studies()
        |> Enum.reject(&(&1.slug == case_study.slug))
        |> Enum.take_random(3)

      conn
      |> assign(:head_title, case_study.title)
      |> assign(:head_description, case_study.excerpt)
      |> assign(
        :head_image,
        Tuist.Environment.app_url(path: case_study.og_image_path)
      )
      |> assign(:head_twitter_card, "summary_large_image")
      |> assign_structured_data(
        get_breadcrumbs_structured_data([
          {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
          {dgettext("marketing", "Customers"), Tuist.Environment.app_url(path: ~p"/customers")},
          {case_study.title, Tuist.Environment.app_url(path: case_study.slug)}
        ])
      )
      |> assign_structured_data(get_case_study_article_structured_data(case_study))
      |> assign(:case_study, case_study)
      |> assign(:related_case_studies, related_case_studies)
      |> render(:case_study, layout: false)
    end
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
         read_more: "<a href=\"#{~p"/blog/2024/11/05/our-pricing-philosophy"}\">#{dgettext("marketing", "read more")}</a>"
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
        path: og_image_path("/marketing/images/og/generated/#{page.slug |> String.split("/") |> List.last()}.jpg")
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

  # Builds a locale-specific OG image path. For English, returns the path as-is.
  # For other locales, inserts the locale before the filename.
  #
  # Examples:
  #   - og_image_path("/marketing/images/og/about.jpg", "en") -> "/marketing/images/og/about.jpg"
  #   - og_image_path("/marketing/images/og/about.jpg", "ko") -> "/marketing/images/og/ko/about.jpg"
  defp og_image_path(path, locale \\ nil) do
    locale = locale || Gettext.get_locale(TuistWeb.Gettext)

    if locale == "en" do
      path
    else
      dirname = Path.dirname(path)
      basename = Path.basename(path)
      Path.join([dirname, locale, basename])
    end
  end
end
