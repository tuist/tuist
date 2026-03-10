defmodule NooraStorybookWeb.Storybook do
  use PhoenixStorybook,
    otp_app: :noora_storybook,
    title: "Noora (#{
      case :application.get_key(:noora, :vsn) do
        {:ok, vsn} -> List.to_string(vsn)
        _ -> "dev"
      end
    })",
    content_path: Path.expand("../../storybook", __DIR__),
    css_path: "/assets/storybook.css",
    js_path: "/assets/storybook.js",
    sandbox_class: "noora-storybook-web",
    color_mode: true,
    color_mode_sandbox_dark_class: "noora-dark"
end
