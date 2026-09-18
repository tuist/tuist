defmodule Atlas.Engineering.Pages.ReservedSlugs do
  @moduledoc """
  Slugs that Pages will never hand out because they collide with existing or
  reasonably-anticipated subdomains under `atlas.tuist.dev`. Serving a page at
  one of these labels would shadow real infrastructure.
  """

  @reserved MapSet.new([
              "www",
              "api",
              "admin",
              "mail",
              "smtp",
              "imap",
              "mcp",
              "static",
              "assets",
              "auth",
              "login",
              "logout",
              "oauth",
              "oauth2",
              "app",
              "dashboard",
              "atlas",
              "status",
              "cdn",
              "docs",
              "help",
              "support",
              "billing",
              "webhooks",
              "ftp",
              "ssh",
              "vpn",
              "ns",
              "ns1",
              "ns2",
              "dns",
              "public",
              "internal",
              "private",
              "test",
              "tests",
              "staging",
              "prod",
              "production",
              "canary",
              "dev",
              "beta",
              "alpha",
              "sso",
              "api-docs",
              "pages"
            ])

  def reserved?(slug) when is_binary(slug), do: MapSet.member?(@reserved, String.downcase(slug))
  def reserved?(_slug), do: true

  def all, do: MapSet.to_list(@reserved)
end
