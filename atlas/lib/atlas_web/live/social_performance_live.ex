defmodule AtlasWeb.SocialPerformanceLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.GTM.SocialPost
  alias Atlas.GTM.SocialPosts

  @periods %{"30" => 30, "90" => 90}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Post performance"))}
  end

  def handle_params(params, _uri, socket) do
    period = if Map.has_key?(@periods, params["period"]), do: params["period"], else: "30"
    posts = SocialPosts.list_posts(days: @periods[period])

    {:noreply,
     socket
     |> assign(:period, period)
     |> assign(:posts, posts)
     |> assign(:summary, SocialPosts.summarize(posts))}
  end

  def render(assigns) do
    ~H"""
    <div id="gtm-social-performance" data-part="gtm-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Post performance")}</h1>
          <p data-part="description">
            {gettext(
              "Posts from connected X accounts, refreshed daily. Engagements are likes, reposts, quotes, replies and bookmarks. Connect an account in Settings → Connections."
            )}
          </p>
        </div>
        <div data-part="header-actions">
          <.button_group id="social-period" size="medium" aria-label={gettext("Period")}>
            <.button_group_item
              :for={{value, label} <- [{"30", gettext("30 days")}, {"90", gettext("90 days")}]}
              id={"social-period-#{value}"}
              label={label}
              patch={~p"/commercial/gtm/social/performance?period=#{value}"}
              data-selected={@period == value}
              aria-current={if(@period == value, do: "true")}
            />
          </.button_group>
        </div>
      </div>

      <section data-part="page-section">
        <.card title={gettext("By account")} icon="users" data-part="ideas-card">
          <.card_section data-part="ideas-table-section">
            <.summary_table
              id="social-by-account"
              rows={@summary.by_account}
              label={gettext("Account")}
            />
          </.card_section>
        </.card>

        <.card title={gettext("By format")} icon="photo" data-part="ideas-card">
          <.card_section data-part="ideas-table-section">
            <.summary_table id="social-by-format" rows={@summary.by_format} label={gettext("Format")} />
          </.card_section>
        </.card>

        <.card title={gettext("Posts")} icon="message_circle" data-part="ideas-card">
          <.card_section data-part="ideas-table-section">
            <.table id="social-posts-table" rows={@posts} row_key={& &1.id}>
              <:col :let={post} label={gettext("Post")}>
                <div data-part="source-entry">
                  <.link href={post.url} target="_blank" rel="noopener" data-part="source-title">
                    {preview(post.text)}
                  </.link>
                  <span data-part="source-description">{post.account_handle}</span>
                </div>
              </:col>
              <:col :let={post} label={gettext("Format")}>
                <.badge_cell
                  label={SocialPosts.format_label(post)}
                  color="neutral"
                  style="light-fill"
                />
              </:col>
              <:col :let={post} label={gettext("Posted")}>
                <.text_cell label={Calendar.strftime(post.posted_at, "%Y-%m-%d")} />
              </:col>
              <:col :let={post} label={gettext("Impressions")}>
                <.text_cell label={format_number(post.impressions)} />
              </:col>
              <:col :let={post} label={gettext("Engagements")}>
                <.text_cell label={format_number(SocialPost.engagements(post))} />
              </:col>
              <:col :let={post} label={gettext("Rate")}>
                <.text_cell label={format_rate(SocialPost.engagement_rate(post))} />
              </:col>
              <:col :let={post} label={gettext("Link clicks")}>
                <.text_cell label={format_number(post.url_clicks)} />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="message_circle"
                  title={gettext("No posts yet")}
                  subtitle={
                    gettext(
                      "Connect an X account in Settings → Connections. Posts appear after the next daily sync."
                    )
                  }
                />
              </:empty_state>
            </.table>
          </.card_section>
        </.card>
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :label, :string, required: true

  defp summary_table(assigns) do
    ~H"""
    <.table id={@id} rows={@rows} row_key={& &1.group}>
      <:col :let={row} label={@label}><.text_cell label={row.group} /></:col>
      <:col :let={row} label={gettext("Posts")}><.text_cell label={format_number(row.posts)} /></:col>
      <:col :let={row} label={gettext("Median impressions")}>
        <.text_cell label={format_number(row.median_impressions)} />
      </:col>
      <:col :let={row} label={gettext("Median engagements")}>
        <.text_cell label={format_number(row.median_engagements)} />
      </:col>
      <:col :let={row} label={gettext("Median rate")}>
        <.text_cell label={format_rate(row.median_engagement_rate)} />
      </:col>
      <:empty_state>
        <.table_empty_state icon="chart_column" title={gettext("No data yet")} subtitle="" />
      </:empty_state>
    </.table>
    """
  end

  defp preview(text) do
    if String.length(text) > 80, do: String.slice(text, 0, 80) <> "…", else: text
  end

  defp format_number(nil), do: "–"
  defp format_number(value) when is_float(value), do: value |> round() |> format_number()

  defp format_number(value) do
    value |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_rate(nil), do: "–"
  defp format_rate(rate), do: :erlang.float_to_binary(rate * 100, decimals: 2) <> "%"
end
