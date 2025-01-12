defmodule TuistWeb.Storybook do
  @moduledoc false
  use PhoenixStorybook,
    otp_app: :tuist_web,
    title: "Noora Storybook",
    content_path: Path.expand("./storybook", __DIR__),
    css_path: "/app/css/app/noora.css",
    js_path: "/app/js/app.js",
    sandbox_class: "tuist-web"
end
