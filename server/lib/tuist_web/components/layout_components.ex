defmodule TuistWeb.LayoutComponents do
  @moduledoc ~S"""
  A collection of components for layouts.
  """
  use TuistWeb, :live_component

  import TuistWeb.CSP, only: [get_csp_nonce: 0]

  attr :current_user, :map, default: nil

  def head_plain_script(assigns) do
    current_user = Map.get(assigns, :current_user)
    plain_authentication_secret = Tuist.Environment.plain_authentication_secret()

    plain_opts =
      Map.merge(
        %{appId: "liveChatApp_01JSH0MMH3KHE7PX1781CV2HZG"},
        if(is_nil(current_user) or is_nil(plain_authentication_secret),
          do: %{},
          else: %{
            customerDetails: %{
              email: current_user.email,
              emailHash:
                :hmac
                |> :crypto.mac(:sha256, plain_authentication_secret, current_user.email)
                |> Base.encode16(case: :lower),
              chatAvatarUrl: Tuist.Accounts.User.gravatar_url(current_user)
            }
          }
        )
      )

    assigns = assign(assigns, :plain_opts, plain_opts)

    ~H"""
    <script :if={Tuist.Environment.analytics_enabled?()} nonce={get_csp_nonce()}>
      (function(d, script) {
        script = d.createElement('script');
        script.async = false;
        script.onload = function(){
          Plain.init(<%= raw JSON.encode!(@plain_opts) %>);
        };
        script.src = 'https://chat.cdn-plain.com/index.js';
        d.getElementsByTagName('head')[0].appendChild(script);
      }(document));
    </script>
    """
  end

  def head_meta_meta_tags(assigns) do
    ~H"""
    <% default_description =
      gettext("Tuist extends Apple's tools, helping you ship apps that stand out.") %>
    <meta name="description" content={assigns[:head_description] || default_description} />
    <%= if not is_nil(assigns[:head_keywords]) do %>
      <meta name="keywords" content={assigns[:head_keywords] |> Enum.join(", ")} />
    <% end %>
    <meta property="og:url" content={Tuist.Environment.app_url(path: "/")} />
    <meta property="og:type" content="website" />
    <meta property="og:title" content={assigns[:head_title] || "Tuist"} />
    <meta property="og:description" content={assigns[:head_description] || default_description} />
    <meta :if={not is_nil(assigns[:head_fediverse_creator])} name="fediverse:creator" content={assigns[:head_fediverse_creator]} />

    <%= if is_nil(assigns[:head_image]) do %>
      <meta
        property="og:image"
        content={Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")}
      />
    <% else %>
      <meta property="og:image" content={assigns[:head_image]} />
    <% end %>
    """
  end

  def head_x_meta_tags(assigns) do
    ~H"""
    <%= if is_nil(assigns[:head_twitter_card]) do %>
      <meta name="twitter:card" content="summary" />
    <% else %>
      <meta name="twitter:card" content={assigns[:head_twitter_card]} />
    <% end %>
    <meta name="twitter:site" content="@tuistdev" />
    <%= if is_nil(assigns[:head_image]) do %>
      <meta
        name="twitter:image"
        content={Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")}
      />
    <% else %>
      <meta name="twitter:image" content={assigns[:head_image]} />
    <% end %>
    <meta name="twitter:title" content={assigns[:head_title] || "Tuist"} />
    <meta
      property="twitter:domain"
      content={Tuist.Environment.app_url(path: "/") |> URI.parse() |> Map.get(:host)}
    />
    <meta property="twitter:url" content={Tuist.Environment.app_url()} />
    """
  end

  def head_analytics_scripts(assigns) do
    posthog_opts =
      Map.merge(
        %{api_host: "https://eu.i.posthog.com"},
        if(TuistWeb.Authentication.authenticated?(assigns),
          do: %{bootstrap: %{distinctID: TuistWeb.Authentication.current_user(assigns).id}},
          else: %{persistence: "memory"}
        )
      )

    assigns = Map.put(assigns, :posthog_opts, posthog_opts)

    ~H"""
    <script :if={Tuist.Environment.analytics_enabled?()} nonce={get_csp_nonce()}>
      globalThis.analyticsEnabled = <%= Tuist.Environment.analytics_enabled?() %>;
    </script>
    <script :if={Tuist.Environment.analytics_enabled?()} nonce={get_csp_nonce()}>
      !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys onSessionId".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
      posthog.init('phc_fpR9c0Hs5H5VXUsupU1I0WlEq366FaZH6HJR3lRIWVR', <%= raw JSON.encode!(@posthog_opts) %> )
    </script>
    """
  end
end
