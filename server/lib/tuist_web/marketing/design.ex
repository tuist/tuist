defmodule TuistWeb.Marketing.Design do
  @moduledoc """
  Decides whether a marketing page renders the redesigned version or the
  legacy one.

  The launch is driven by a single FunWithFlags boolean (see
  `Tuist.FeatureFlags.new_marketing_enabled?/1`). Anonymous traffic follows
  the global flag. Authenticated users are checked as flag actors, so the
  redesign can be previewed before the global flip by enabling the flag for
  a specific user:

      FunWithFlags.enable(:new_marketing, for_actor: user)

  Pages that have migrated call `new?/1` to pick the template, and assign
  the result as `:new_design` so the root layout links bundle-new.css
  instead of bundle.css — the two designs restyle the same selectors, so
  their stylesheets are never loaded together.

  Controllers pass the `conn` (the marketing pipeline fetches the current
  user). LiveViews mount the current user
  (`on_mount {TuistWeb.Authentication, :mount_current_user}`) and pass it
  directly.

  Because previews are user-gated, responses for authenticated visitors can
  differ from the anonymous ones at the same URL; the marketing
  cache-control plug keeps those out of shared caches (see
  `TuistWeb.Marketing.MarketingController.put_resp_header_cache_control/2`).
  """

  alias Tuist.FeatureFlags

  @doc """
  Whether the redesigned templates should render for this request. Takes the
  `conn` in controllers, or the current user (or `nil`) in a LiveView's
  `mount/3`.
  """
  def new?(%Plug.Conn{} = conn) do
    new?(conn.assigns[:current_user])
  end

  def new?(current_user) do
    FeatureFlags.new_marketing_enabled?(current_user)
  end
end
