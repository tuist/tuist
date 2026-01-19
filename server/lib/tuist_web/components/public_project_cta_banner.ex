defmodule TuistWeb.Components.PublicProjectCTABanner do
  @moduledoc """
  A CTA banner component shown to unauthenticated users viewing the tuist/tuist project dashboard.
  """
  use TuistWeb, :html
  use Noora

  import Noora.Icon, only: [close: 1]

  def public_project_cta_banner(assigns) do
    ~H"""
    <div
      id="public-project-cta-banner"
      class="public-project-cta-banner"
      phx-hook="PublicProjectCTABanner"
    >
      <div data-part="background">
        <div data-part="shell">
          <.banner_shell />
        </div>
        <div data-part="gradient-right"></div>
        <div data-part="gradient-left"></div>
      </div>
      <div data-part="content">
        <p>
          {dgettext(
            "dashboard",
            "This is a public dashboard for the tuist/tuist project."
          )}
          <br />
          {dgettext(
            "dashboard",
            "Ready to speed up your builds and unlock insights for your app?"
          )}
        </p>
        <div data-part="actions">
          <.button
            label={dgettext("dashboard", "Get started")}
            variant="primary"
            size="large"
            href="https://docs.tuist.dev/en/"
            target="_blank"
          />
          <.button
            label={dgettext("dashboard", "Talk to us")}
            variant="secondary"
            href="https://cal.com/team/tuist/cloud"
            target="_blank"
            size="large"
          />
        </div>
      </div>
      <button data-part="dismiss" type="button" aria-label="Dismiss">
        <.close />
      </button>
    </div>
    """
  end

  def show_banner?(account_name, project_name, current_user) do
    is_nil(current_user) and account_name == "tuist" and project_name == "tuist"
  end

  defp banner_shell(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width="108" height="172" viewBox="0 0 108 172" fill="none">
      <path
        d="M21.0029 0.347656C23.5384 0.347656 26.05 0.44546 28.5371 0.643555L29.6016 0.734375L29.9102 0.762695L29.917 1.07324L32.8213 124.748C36.8079 115.532 40.3379 105.941 43.5488 96.2139C51.3004 72.5864 57.3619 48.1538 62.2422 23.4883L62.3301 23.0449L62.7354 23.2432C68.2085 25.911 73.3775 29.0906 78.1943 32.708L78.3613 32.832L78.3301 33.0381C73.6733 63.4213 67.6141 93.7789 57.8584 123.136C59.1441 121.697 60.4101 120.247 61.6562 118.791C74.8972 102.992 85.7953 85.1001 95.1982 66.6318L95.4453 66.1465L95.7812 66.5752C99.8442 71.7538 103.555 77.4341 106.496 83.4092L106.569 83.5586L106.499 83.709C97.3653 103.361 85.4461 124.535 70.5967 142.344C80.1933 137.754 89.3437 132 97.9355 125.421L98.2197 125.203L98.4287 125.494C101.835 130.238 104.813 135.305 107.314 140.653L107.412 140.861L107.259 141.033C61.0851 192.353 -19.0947 192.344 -65.2588 141.033L-65.4121 140.861L-65.3154 140.653C-62.8171 135.305 -59.8321 130.241 -56.4258 125.498L-56.2168 125.206L-55.9316 125.425C-47.3226 132.021 -38.1549 137.782 -28.5352 142.378C-38.5949 130.236 -47.1321 116.749 -54.502 103.719L-54.5049 103.714C-58.0814 97.1415 -61.3988 90.4801 -64.5059 83.7334L-64.5752 83.583L-64.5029 83.4346C-61.5619 77.4564 -57.851 71.7664 -53.7783 66.5781L-53.4414 66.1494L-53.1943 66.6348C-43.7909 85.1041 -32.8892 102.997 -19.6504 118.797H-19.6514C-18.3985 120.287 -17.1259 121.754 -15.8359 123.201C-25.6032 93.8266 -31.6665 63.4448 -36.3262 33.041L-36.3584 32.8359L-36.1914 32.7109C-31.3746 29.0935 -26.2056 25.9139 -20.7324 23.2461L-20.3271 23.0479L-20.2393 23.4912C-15.3591 48.1532 -9.29825 72.5855 -1.54688 96.2158L-0.251953 100.027C2.62394 108.412 5.68566 116.723 9.18066 124.789L12.0889 1.07324L12.0967 0.763672L12.4043 0.734375C15.2392 0.472002 18.1057 0.347663 21.0029 0.347656Z"
        stroke="url(#paint0_linear_5672_78549)"
        stroke-opacity="0.2"
        stroke-width="0.69537"
      />
      <defs>
        <linearGradient
          id="paint0_linear_5672_78549"
          x1="21"
          y1="0.695312"
          x2="21"
          y2="179.172"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#6F2CFF" />
          <stop offset="1" stop-color="white" />
        </linearGradient>
      </defs>
    </svg>
    """
  end
end
