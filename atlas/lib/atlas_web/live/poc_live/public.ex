defmodule AtlasWeb.POCLive.Public do
  @moduledoc false

  use AtlasWeb, :live_view
  use Noora

  alias Atlas.Accounts.POCs
  alias Atlas.Accounts.POCs.AccessRequest
  alias Atlas.Accounts.POCs.Notifier, as: POCNotifier
  alias Atlas.Users
  alias AtlasWeb.Markdown
  alias AtlasWeb.POCPublicController

  @impl true
  def mount(%{"public_token" => token}, session, socket) do
    case POCs.get_poc_by_public_token(token) do
      %{} = poc ->
        {:ok, mount_for_poc(socket, poc, session)}

      nil ->
        {:ok,
         socket
         |> assign(:page_title, "POC not available")
         |> assign(:view_mode, :not_found)
         |> assign(:poc, nil)}
    end
  end

  defp mount_for_poc(socket, poc, session) do
    cookie = Map.get(session, POCPublicController.session_cookie_name(poc))

    if authenticated_atlas_user?(session) or match?({:ok, _request}, POCs.verify_session_cookie(poc, cookie)) do
      socket
      |> assign(:page_title, poc.title)
      |> assign(:view_mode, :brief)
      |> assign(:poc, poc)
    else
      socket
      |> assign(:page_title, "#{poc.title} · Access required")
      |> assign(:view_mode, :gate)
      |> assign(:poc, poc)
      |> assign(:form, to_form(%{"email" => ""}, as: :access))
      |> assign(:pending_request, nil)
      |> assign(:connect_ip, connect_ip(socket))
      |> assign(:connect_user_agent, connect_user_agent(socket))
    end
  end

  defp authenticated_atlas_user?(%{"user_id" => user_id}) when is_binary(user_id),
    do: not is_nil(Users.get_user(user_id))

  defp authenticated_atlas_user?(_session), do: false

  @impl true
  def handle_event("request_access", %{"access" => %{"email" => email}}, socket) do
    poc = socket.assigns.poc
    normalized = email |> to_string() |> String.trim() |> String.downcase()

    cond do
      normalized == "" ->
        {:noreply, put_flash(socket, :error, "Enter your email to request access.")}

      not POCs.authorized_email?(poc, normalized) ->
        # We do not tell the visitor whether the email is on the account or
        # not. The response is the same either way so a leaked link cannot be
        # used to probe the customer's contact list.
        {:noreply, put_access_pending_flash(socket, normalized)}

      true ->
        case POCs.create_access_request(poc, normalized,
               ip: socket.assigns[:connect_ip],
               user_agent: socket.assigns[:connect_user_agent]
             ) do
          {:ok, request, plaintext_token} ->
            POCNotifier.send_verification_email(poc, request, plaintext_token)

            {:ok, request} =
              case POCNotifier.send_slack_request(poc, request) do
                {:ok, {channel, ts}} -> POCs.record_slack_message(request, channel, ts)
                _ -> {:ok, request}
              end

            POCs.subscribe_to_access_request(request.id)

            {:noreply,
             socket
             |> assign(:pending_request, request)
             |> put_access_pending_flash(normalized)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not submit that request. Try again.")}
        end
    end
  end

  # Swoosh's Test adapter delivers by sending `{:email, %Swoosh.Email{}}` to
  # the caller. When `send_verification_email/3` runs inside this LiveView
  # process, that message lands here. Ignore it (and any other unrelated
  # message) instead of crashing.
  @impl true
  def handle_info({:email, %Swoosh.Email{}}, socket), do: {:noreply, socket}

  def handle_info({:poc_access_request_updated, %AccessRequest{} = request}, socket) do
    socket = assign(socket, :pending_request, request)

    cond do
      AccessRequest.active?(request) ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/p/pocs/#{socket.assigns.poc.public_token}/session/#{request.id}"
         )}

      request.denied_at ->
        {:noreply, put_flash(socket, :error, "Access was denied by the Tuist team.")}

      true ->
        {:noreply, socket}
    end
  end

  defp put_access_pending_flash(socket, email) do
    put_flash(
      socket,
      :info,
      "If #{email} is authorized, we sent a verification email. Confirm it and keep this tab open. Access unlocks automatically once the Tuist team approves."
    )
  end

  defp connect_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} -> address |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp connect_user_agent(socket) do
    case get_connect_info(socket, :user_agent) do
      ua when is_binary(ua) -> String.slice(ua, 0, 512)
      _ -> nil
    end
  end

  @impl true
  def render(%{view_mode: :not_found} = assigns) do
    ~H"""
    <section id="poc-public-not-found">
      <h1>POC not available</h1>
      <p>
        This proof of concept is either private or the link is no longer valid. Please reach out to your Tuist contact for a fresh link.
      </p>
    </section>
    """
  end

  def render(%{view_mode: :gate} = assigns) do
    ~H"""
    <div id="poc-public-gate" style={theme_style(@poc)}>
      <div data-part="frame">
        <div data-part="content">
          <div data-part="brand">
            <img
              :if={brand_avatar_url(@poc)}
              src={brand_avatar_url(@poc)}
              alt={brand_label(@poc)}
            />
            <span>{brand_label(@poc)}</span>
            <span :if={brand_domain(@poc)} data-part="brand-domain">
              · {brand_domain(@poc)}
            </span>
          </div>
          <div data-part="header">
            <h1 data-part="title">Access required</h1>
            <span data-part="subtitle">
              This POC brief is private. Enter your work email and the Tuist team will grant access. The page opens automatically once approved.
            </span>
          </div>

          <%= if @pending_request do %>
            <div data-part="status-card">
              <span data-part="status-title">Waiting on the Tuist team</span>
              <p>
                Check your inbox for a verification email at <strong>{@pending_request.email}</strong>. Once you confirm,
                the Tuist team can grant access and this page will unlock on
                its own.
              </p>
              <ol data-part="status-steps">
                <li data-checked={to_string(not is_nil(@pending_request.verified_at))}>
                  Email confirmed
                </li>
                <li data-checked={to_string(not is_nil(@pending_request.approved_at))}>
                  Approved by the Tuist team
                </li>
              </ol>
            </div>
          <% else %>
            <.form for={@form} id="poc-access-form" phx-submit="request_access" data-part="form">
              <.text_input
                field={@form[:email]}
                id="poc-access-email"
                label="Work email"
                type="email"
                placeholder="you@company.com"
                show_prefix={false}
                required
              />
              <Noora.Button.button
                type="submit"
                variant="primary"
                size="large"
                label="Request access"
              />
            </.form>
          <% end %>
        </div>
      </div>
      <div data-part="background">
        <div data-part="top-right-gradient"></div>
        <div data-part="bottom-left-gradient"></div>
      </div>
    </div>
    """
  end

  def render(%{view_mode: :brief} = assigns) do
    ~H"""
    <section id="poc-public" style={theme_style(@poc)}>
      <article data-part="article">
        <header data-part="header">
          <div data-part="brand">
            <img
              :if={brand_avatar_url(@poc)}
              src={brand_avatar_url(@poc)}
              alt={brand_label(@poc)}
            />
            <span>{brand_label(@poc)}</span>
            <span :if={brand_domain(@poc)} data-part="brand-domain">
              · {brand_domain(@poc)}
            </span>
          </div>
          <span data-part="eyebrow">Proof of Concept</span>
          <h1>{@poc.title}</h1>
          <Markdown.content
            :if={@poc.summary}
            id={"poc-#{@poc.id}-lede"}
            body={@poc.summary}
            heading_offset={2}
            data-part="lede"
          />
          <div data-part="status-row">
            <span data-part="status-chip">{status_label(@poc.status)}</span>
            <span :if={hosting_label(@poc.hosting)}>{hosting_label(@poc.hosting)}</span>
          </div>
        </header>

        <section data-part="section">
          <header>
            <h2>Context</h2>
            <p>Snapshot of the environment captured when the POC started.</p>
          </header>
          <%= if context_present?(@poc.context) do %>
            <dl data-part="context-grid">
              <div :if={@poc.context.developer_count} data-part="context-item">
                <dt>Developers</dt>
                <dd>{@poc.context.developer_count}</dd>
              </div>
              <div :if={@poc.context.ci_solution} data-part="context-item">
                <dt>CI</dt>
                <dd>{humanize_value(@poc.context.ci_solution)}</dd>
              </div>
              <div :if={@poc.context.git_forge} data-part="context-item">
                <dt>Git</dt>
                <dd>{humanize_value(@poc.context.git_forge)}</dd>
              </div>
              <div :if={@poc.context.primary_language} data-part="context-item">
                <dt>Primary language</dt>
                <dd>{humanize_value(@poc.context.primary_language)}</dd>
              </div>
              <div :if={not is_nil(@poc.context.monorepo)} data-part="context-item">
                <dt>Repository shape</dt>
                <dd>{if @poc.context.monorepo, do: "Monorepo", else: "Polyrepo"}</dd>
              </div>
            </dl>
            <Markdown.content
              :if={@poc.context.notes}
              id={"poc-#{@poc.id}-context-notes"}
              body={@poc.context.notes}
              heading_offset={2}
              data-part="context-notes"
            />
          <% else %>
            <p data-part="empty">Context has not been captured yet.</p>
          <% end %>
        </section>

        <section data-part="section">
          <header>
            <h2>Scope</h2>
            <p>What we are evaluating during this POC.</p>
          </header>
          <%= if @poc.scope_features != [] do %>
            <ul data-part="scope-features">
              <li :for={scope <- @poc.scope_features}>
                {scope.feature_interest.title}
              </li>
            </ul>
          <% else %>
            <p data-part="empty">Scope has not been defined yet.</p>
          <% end %>
        </section>

        <section data-part="section">
          <header>
            <h2>Timeline</h2>
            <p>Significant events, decisions, and milestones.</p>
          </header>
          <% timeline = combined_timeline(@poc) %>
          <%= if timeline != [] do %>
            <ol data-part="timeline">
              <li
                :for={item <- timeline}
                data-part="timeline-entry"
                data-future={to_string(item.future?)}
              >
                <time data-part="timeline-date" datetime={Date.to_iso8601(item.occurred_on)}>
                  {timeline_date_label(item)}
                </time>
                <div data-part="timeline-body">
                  <span data-part="timeline-kind">{humanize_value(item.kind)}</span>
                  <h3 data-part="timeline-title">{item.title}</h3>
                  <Markdown.content
                    :if={item.body}
                    id={"poc-#{@poc.id}-entry-#{item.id}"}
                    body={item.body}
                    heading_offset={2}
                    data-part="timeline-note"
                  />
                </div>
              </li>
            </ol>
          <% else %>
            <p data-part="empty">No events recorded yet.</p>
          <% end %>
        </section>

        <footer data-part="footer">
          Last updated {format_date(DateTime.to_date(@poc.updated_at))} · Prepared by Tuist
        </footer>
      </article>
    </section>
    """
  end

  defp theme_style(%{brand_accent_color: color}) when is_binary(color), do: "--poc-accent: #{color};"

  defp theme_style(_poc), do: nil

  defp brand_label(%{account: %{name: name}}) when is_binary(name) and name != "", do: name
  defp brand_label(_poc), do: "Tuist"

  defp brand_domain(%{account: %{primary_domain: domain}}) when is_binary(domain) and domain != "", do: domain

  defp brand_domain(_poc), do: nil

  defp brand_avatar_url(%{brand_logo_url: url}) when is_binary(url) and url != "", do: url

  defp brand_avatar_url(poc) do
    case brand_domain(poc) do
      nil -> nil
      domain -> "https://icons.duckduckgo.com/ip3/#{domain}.ico"
    end
  end

  defp status_label("draft"), do: "Draft"
  defp status_label("active"), do: "In progress"
  defp status_label("closed_won"), do: "Completed"
  defp status_label("closed_lost"), do: "Closed"
  defp status_label(other), do: humanize_value(other)

  defp hosting_label("cloud"), do: "Tuist-hosted"
  defp hosting_label("self_hosted"), do: "Self-hosted"
  defp hosting_label(_hosting), do: nil

  # Merges real timeline entries with synthesized "start" / "end" markers taken
  # from the POC's agreed window. Sorted desc by date so the most recent
  # (or upcoming) item is at the top of the rail.
  defp combined_timeline(poc) do
    real_entries =
      Enum.map(poc.timeline_entries, fn entry ->
        %{
          id: entry.id,
          occurred_on: entry.occurred_on,
          title: entry.title,
          kind: entry.kind,
          body: entry.body,
          future?: false
        }
      end)

    today = Date.utc_today()

    (real_entries ++ schedule_timeline_entries(poc, today))
    |> Enum.sort_by(& &1.occurred_on, {:desc, Date})
  end

  defp schedule_timeline_entries(poc, today) do
    []
    |> maybe_add_start_entry(poc, today)
    |> maybe_add_end_entry(poc, today)
  end

  defp maybe_add_start_entry(entries, %{starts_on: nil}, _today), do: entries

  defp maybe_add_start_entry(entries, %{starts_on: %Date{} = starts_on}, today) do
    if Date.after?(starts_on, today) do
      [
        %{id: "start", occurred_on: starts_on, title: "POC begins", kind: "milestone", body: nil, future?: true}
        | entries
      ]
    else
      entries
    end
  end

  defp maybe_add_end_entry(entries, %{ends_on: nil}, _today), do: entries

  defp maybe_add_end_entry(entries, %{ends_on: %Date{} = ends_on}, today) do
    future? = Date.compare(ends_on, today) != :lt

    [
      %{
        id: "end",
        occurred_on: ends_on,
        title: end_entry_title(ends_on, today),
        kind: "milestone",
        body: nil,
        future?: future?
      }
      | entries
    ]
  end

  defp end_entry_title(%Date{} = ends_on, today) do
    case Date.compare(ends_on, today) do
      :gt -> "POC ends"
      :eq -> "POC ends today"
      :lt -> "POC ended"
    end
  end

  defp timeline_date_label(%{future?: true, occurred_on: date}) do
    case Date.diff(date, Date.utc_today()) do
      0 -> "Today"
      1 -> "In 1 day"
      diff when diff > 0 -> "In #{diff} days"
      _ -> format_date(date)
    end
  end

  defp timeline_date_label(%{occurred_on: date}), do: format_date(date)

  defp context_present?(nil), do: false

  defp context_present?(context) do
    Enum.any?(
      [
        context.developer_count,
        context.ci_solution,
        context.git_forge,
        context.primary_language,
        context.monorepo,
        context.notes
      ],
      &(not is_nil(&1))
    )
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp humanize_value(value) when is_binary(value), do: value |> String.replace("_", " ") |> String.capitalize()
  defp humanize_value(value), do: to_string(value)
end
