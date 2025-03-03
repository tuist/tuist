defmodule TuistWeb.Storybook do
  @moduledoc false
  use PhoenixStorybook,
    otp_app: :tuist_web,
    title: "Noora Storybook",
    content_path: Path.expand("./storybook", __DIR__),
    css_path: "/storybook/assets/bundle.css",
    js_path: "/storybook/assets/bundle.js",
    js_script_type: "module",
    sandbox_class: "tuist-web",
    color_mode: true,
    color_mode_sandbox_dark_class: "noora-dark"
end
