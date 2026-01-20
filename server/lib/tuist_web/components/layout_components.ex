defmodule TuistWeb.LayoutComponents do
  @moduledoc ~S"""
  A collection of components for layouts.
  """
  use TuistWeb, :live_component

  import TuistWeb.CSP, only: [get_csp_nonce: 0]

  attr(:current_user, :map, default: nil)

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
    <script
      :if={Tuist.Environment.analytics_enabled?() and not Map.get(assigns, :plain_disabled?, false)}
      nonce={get_csp_nonce()}
    >
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
      dgettext("dashboard", "Tuist extends Apple's tools, helping you ship apps that stand out.") %>
    <meta name="description" content={assigns[:head_description] || default_description} />
    <%= if not is_nil(assigns[:head_keywords]) do %>
      <meta name="keywords" content={assigns[:head_keywords] |> Enum.join(", ")} />
    <% end %>
    <meta property="og:url" content={Tuist.Environment.app_url(path: "/")} />
    <meta property="og:type" content="website" />
    <meta property="og:title" content={assigns[:head_title] || "Tuist"} />
    <meta property="og:description" content={assigns[:head_description] || default_description} />
    <meta
      :if={not is_nil(assigns[:head_fediverse_creator])}
      name="fediverse:creator"
      content={assigns[:head_fediverse_creator]}
    />

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

  attr(:page_section, :string, default: nil)

  def head_analytics_scripts(assigns) do
    analytics_enabled =
      Tuist.Environment.analytics_enabled?() and not Map.get(assigns, :analytics_disabled?, false)

    posthog_opts =
      Map.merge(
        %{api_host: Tuist.Environment.posthog_url(), person_profiles: "identified_only"},
        if(TuistWeb.Authentication.authenticated?(assigns),
          do: %{bootstrap: %{distinctID: TuistWeb.Authentication.current_user(assigns).id}},
          else: %{persistence: "memory"}
        )
      )

    posthog_identity =
      if is_nil(assigns[:current_user]) do
        nil
      else
        {assigns[:current_user].id, %{email: assigns[:current_user].email}}
      end

    posthog_alias =
      case assigns[:current_user] do
        %{account: %{name: name}} when is_binary(name) -> name
        _ -> nil
      end

    posthog_groups =
      []
      |> maybe_add_group("project", assigns[:selected_project])
      |> maybe_add_group("account", assigns[:selected_account])

    analytics_opts = %{
      enabled: analytics_enabled,
      page_section: assigns.page_section
    }

    assigns =
      assigns
      |> assign(:analytics_enabled, analytics_enabled)
      |> assign(:posthog_opts, posthog_opts)
      |> assign(:analytics_opts, analytics_opts)
      |> assign(:posthog_identity, posthog_identity)
      |> assign(:posthog_alias, posthog_alias)
      |> assign(:posthog_groups, posthog_groups)

    ~H"""
    <script nonce={get_csp_nonce()}>
      globalThis.analytics = <%= raw JSON.encode!(@analytics_opts) %>;
    </script>
    <script :if={@analytics_enabled} nonce={get_csp_nonce()}>
      !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init Ce js Ls Te Fs Ds capture Ye calculateEventProperties Us register register_once register_for_session unregister unregister_for_session Ws getFeatureFlag getFeatureFlagPayload isFeatureEnabled reloadFeatureFlags updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures on onFeatureFlags onSurveysLoaded onSessionId getSurveys getActiveMatchingSurveys renderSurvey canRenderSurvey canRenderSurveyAsync identify setPersonProperties group resetGroups setPersonPropertiesForFlags resetPersonPropertiesForFlags setGroupPropertiesForFlags resetGroupPropertiesForFlags reset get_distinct_id getGroups get_session_id get_session_replay_url alias set_config startSessionRecording stopSessionRecording sessionRecordingStarted captureException loadToolbar get_property getSessionProperty Bs zs createPersonProfile Hs Ms Gs opt_in_capturing opt_out_capturing has_opted_in_capturing has_opted_out_capturing get_explicit_consent_status is_capturing clear_opt_in_out_capturing Ns debug L qs getPageViewId captureTraceFeedback captureTraceMetric".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
      posthog.init('<%= Tuist.Environment.posthog_api_key() %>', <%= raw JSON.encode!(@posthog_opts) %>)
    </script>
    <script
      :if={@analytics_enabled and not is_nil(@posthog_identity)}
      nonce={get_csp_nonce()}
    >
      posthog.identify('<%= elem(@posthog_identity, 0) %>', <%= raw JSON.encode!(elem(@posthog_identity, 1)) %>)
    </script>
    <script
      :if={@analytics_enabled and not is_nil(@posthog_alias)}
      nonce={get_csp_nonce()}
    >
      posthog.alias('<%= @posthog_alias %>')
    </script>
    <script
      :for={{group_type, group_key, group_properties} <- @posthog_groups}
      :if={@analytics_enabled and length(@posthog_groups) > 0}
      nonce={get_csp_nonce()}
    >
      posthog.group('<%= group_type %>', '<%= group_key %>', <%= raw JSON.encode!(group_properties) %>)
    </script>
    <script
      :if={@analytics_enabled and not is_nil(@analytics_opts.page_section)}
      nonce={get_csp_nonce()}
    >
      posthog.register({page_section: '<%= @analytics_opts.page_section %>'})
    </script>
    """
  end

  defp maybe_add_group(groups, _group_type, nil), do: groups

  defp maybe_add_group(groups, group_type, %{name: name} = entity) when is_binary(name) do
    group_key = entity.id
    group_properties = %{name: name}
    groups ++ [{group_type, group_key, group_properties}]
  end

  defp maybe_add_group(groups, _group_type, _entity), do: groups
end
