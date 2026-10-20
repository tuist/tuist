defmodule AtlasWeb.AccountLive.Formatters do
  @moduledoc false

  use AtlasWeb, :html

  alias Atlas.Accounts.Account.Address
  alias Atlas.Accounts.Account.Billing
  alias Atlas.Accounts.Account.Signatory
  alias Atlas.Slack.User, as: SlackUser

  @slack_control_pattern ~r/<([^>\n]+)>/
  @slack_code_pattern ~r/(```.*?```|`[^`\n]*`)/s

  def event_title(%{source: "atlas", kind: "note"}), do: gettext("Note")
  def event_title(%{title: title}), do: title

  def event_card_body(%{body: nil}), do: nil
  def event_card_body(%{body: ""}), do: nil
  def event_card_body(%{body: body}), do: body

  def event_card_body_html(event) do
    case event_card_body(event) do
      nil -> nil
      body -> body |> render_markdown() |> raw()
    end
  end

  def event_author_name(%{author: %{name: name}}) when is_binary(name) and name != "", do: name
  def event_author_name(%{author: %{email: email}}) when is_binary(email), do: email
  def event_author_name(_event), do: nil

  def event_icon(%{kind: "note"}), do: "pencil"
  def event_icon(%{kind: "deal"}), do: "trending_up"
  def event_icon(%{kind: "term"}), do: "calendar_week"
  def event_icon(%{kind: "meeting"}), do: "calendar_week"
  def event_icon(%{kind: "company"}), do: "building"
  def event_icon(%{kind: "email"}), do: "mail"
  def event_icon(%{kind: "feedback"}), do: "message_circle"
  def event_icon(%{source: "linkedin"}), do: "message_circle"
  def event_icon(%{kind: "workspace"}), do: "folder"
  def event_icon(%{kind: "lead"}), do: "info_circle"
  def event_icon(_event), do: "file_text"

  def contact_modal_submit_label(:create, _contact), do: gettext("Add Contact")
  def contact_modal_submit_label(:edit, _contact), do: gettext("Save Changes")

  def term_modal_submit_label(:create), do: gettext("Add Term")
  def term_modal_submit_label(:edit), do: gettext("Save Changes")

  def contact_avatar_color(contact) do
    ~w(gray red orange yellow azure blue purple pink)
    |> Enum.at(:erlang.phash2(contact.full_name || contact.email, 8))
  end

  def select_value(nil), do: nil
  def select_value(value) when is_atom(value), do: Atom.to_string(value)
  def select_value(value), do: to_string(value)

  def stripe_customer_url(stripe_customer_id) do
    "https://dashboard.stripe.com/customers/" <> stripe_customer_id
  end

  def show_invoices_card?(account, %{invoices: invoices}) do
    stripe_customer?(account) or invoices != []
  end

  def show_billing_card?(account) do
    not Address.empty?(account.address) or
      not Billing.empty?(account.billing) or
      not Signatory.empty?(account.signatory)
  end

  def address_value(nil, _field), do: "-"
  def address_value(address, field), do: Map.get(address, field) || "-"

  def billing_value(nil, _field), do: "-"
  def billing_value(billing, field), do: Map.get(billing, field) || "-"

  def signatory_value(nil, _field), do: "-"
  def signatory_value(signatory, field), do: Map.get(signatory, field) || "-"

  def term_window(%{start_date: start, end_date: nil}), do: format_date(start)

  def term_window(%{start_date: start, end_date: ending}), do: "#{format_date(start)} - #{format_date(ending)}"

  def term_seats(%{seats: nil}), do: "-"
  def term_seats(%{seats: seats}), do: Integer.to_string(seats)

  def term_currency(%{currency: nil}, account), do: account.currency
  def term_currency(%{currency: currency}, _account), do: currency

  def invoice_date(%{due_date: date}), do: date

  def invoice_number(%{number: number}) when is_binary(number) and number != "", do: number
  def invoice_number(_invoice), do: "-"

  def invoice_amount(%{amount_value: value}), do: value
  def invoice_amount(_), do: nil

  def invoice_currency(%{amount_currency: currency}), do: currency
  def invoice_currency(_), do: nil

  def invoice_url(%{stripe_url: url}) when is_binary(url), do: url
  def invoice_url(_), do: nil

  def empty_invoices_title(%{source: :stripe}, _account), do: gettext("No invoices in Stripe yet")
  def empty_invoices_title(_, _account), do: gettext("No upcoming invoices")

  def empty_invoices_subtitle(%{source: :stripe}, _account),
    do: gettext("Invoices created for this customer in Stripe will appear here automatically.")

  def empty_invoices_subtitle(_, %{stripe_customer_id: nil}),
    do: gettext("Add a Stripe customer ID to surface invoices automatically.")

  def empty_invoices_subtitle(_, _account), do: gettext("Nothing scheduled.")

  def stripe_customer?(%{stripe_customer_id: customer_id}) when is_binary(customer_id) do
    String.trim(customer_id) != ""
  end

  def stripe_customer?(_account), do: false

  def website_url(primary_domain) do
    "https://" <> primary_domain
  end

  def overview_card_style(%{primary_domain: nil}), do: nil

  def overview_card_style(%{primary_domain: domain}) do
    "--account-logo: url('#{AtlasWeb.RevenueComponents.domain_favicon_url(domain, 128)}')"
  end

  def overview_summary_html(markdown) when is_binary(markdown) do
    markdown
    |> render_markdown()
    |> raw()
  end

  def overview_summary_html(_), do: nil

  def slack_message_html(text, mention_labels \\ %{})

  def slack_message_html(text, mention_labels) when is_binary(text) and text != "" do
    text
    |> slack_mrkdwn_to_markdown(mention_labels)
    |> MDEx.to_html!(
      extension: [autolink: true, strikethrough: true],
      render: [hardbreaks: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> raw()
  end

  def slack_message_html(_text, _mention_labels), do: nil

  def slack_mention_labels(event, replies) do
    replies
    |> Enum.reduce(slack_event_mention_labels(event), fn
      %{slack_user: %SlackUser{slack_user_id: user_id} = slack_user}, labels
      when is_binary(user_id) and user_id != "" ->
        Map.put(labels, user_id, SlackUser.best_display_name(slack_user))

      _reply, labels ->
        labels
    end)
  end

  defp render_markdown(markdown) do
    MDEx.to_html!(markdown,
      extension: [table: true, strikethrough: true, autolink: true, tasklist: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
  end

  defp slack_mrkdwn_to_markdown(text, mention_labels) do
    text
    |> then(
      &Regex.replace(@slack_control_pattern, &1, fn original, control ->
        slack_control_to_markdown(original, control, mention_labels)
      end)
    )
    |> String.replace("&lt;", "\\<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> separate_slack_quote_blocks()
    |> normalize_slack_emphasis()
  end

  defp slack_control_to_markdown(original, control, mention_labels) do
    cond do
      String.starts_with?(control, ["http://", "https://", "mailto:"]) ->
        slack_link_to_markdown(original, control)

      String.starts_with?(control, "@") ->
        slack_mention_to_markdown(control, mention_labels)

      String.starts_with?(control, "#") ->
        slack_channel_to_markdown(control)

      String.starts_with?(control, "!") ->
        slack_special_to_markdown(control)

      true ->
        escape_markdown_angles(original)
    end
  end

  defp slack_link_to_markdown(original, control) do
    case String.split(control, "|", parts: 2) do
      [url, label] ->
        "[#{escape_markdown_label(label)}](#{escape_markdown_url(url)})"

      [url] ->
        label = if String.starts_with?(url, "mailto:"), do: String.trim_leading(url, "mailto:"), else: url
        "[#{escape_markdown_label(label)}](#{escape_markdown_url(url)})"

      _parts ->
        escape_markdown_angles(original)
    end
  end

  defp slack_mention_to_markdown(control, mention_labels) do
    [user_id | label] = String.split(control, "|", parts: 2)
    user_id = String.trim_leading(user_id, "@")
    fallback = label |> List.first() |> present_slack_label(user_id)

    "@" <> Map.get(mention_labels, user_id, fallback)
  end

  defp slack_channel_to_markdown(control) do
    [channel_id | label] = String.split(control, "|", parts: 2)
    channel_id = String.trim_leading(channel_id, "#")
    "#" <> (label |> List.first() |> present_slack_label(channel_id))
  end

  defp slack_special_to_markdown(control) do
    [special | label] = String.split(control, "|", parts: 2)

    case List.first(label) do
      nil ->
        special
        |> String.trim_leading("!")
        |> String.split("^", parts: 2)
        |> List.first()
        |> then(&("@" <> &1))

      value ->
        value
    end
  end

  defp present_slack_label(nil, fallback), do: fallback

  defp present_slack_label(label, fallback) do
    label =
      label
      |> String.trim_leading("@")
      |> String.trim_leading("#")

    case label do
      "" -> fallback
      value -> value
    end
  end

  defp escape_markdown_angles(text) do
    text
    |> String.replace("<", "\\<")
    |> String.replace(">", "\\>")
  end

  defp escape_markdown_label(label) do
    label
    |> String.replace("\\", "\\\\")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
  end

  defp escape_markdown_url(url) do
    url
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end

  defp separate_slack_quote_blocks(text) do
    {lines, _quoted?} =
      text
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], false}, fn line, {lines, previous_quoted?} ->
        quoted? = String.starts_with?(String.trim_leading(line), ">")
        needs_separator? = previous_quoted? and not quoted? and String.trim(line) != ""
        lines = if needs_separator?, do: [line, "" | lines], else: [line | lines]

        {lines, quoted?}
      end)

    lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp normalize_slack_emphasis(text) do
    @slack_code_pattern
    |> Regex.split(text, include_captures: true)
    |> Enum.map_join(fn
      "`" <> _rest = code ->
        code

      segment ->
        segment
        |> then(&Regex.replace(~r/(?<!\*)\*([^*\n]+)\*(?!\*)/u, &1, "**\\1**"))
        |> then(&Regex.replace(~r/(?<!~)~([^~\n]+)~(?!~)/u, &1, "~~\\1~~"))
    end)
  end

  defp slack_event_mention_labels(%{metadata: %{"author_slack_user_id" => user_id, "author_name" => name}})
       when is_binary(user_id) and user_id != "" and is_binary(name) and name != "" do
    %{user_id => name}
  end

  defp slack_event_mention_labels(_event), do: %{}

  def format_date(nil), do: "-"
  def format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  def format_datetime(nil), do: "-"
  def format_datetime(%DateTime{} = date_time), do: Calendar.strftime(date_time, "%b %d, %Y")

  def slack_event_author(%{metadata: %{"author_name" => name}}) when is_binary(name) and name != "", do: name

  def slack_event_author(_event), do: gettext("Unknown")

  def slack_event_author_avatar(%{metadata: %{"author_avatar_url" => url}}) when is_binary(url) and url != "", do: url

  def slack_event_author_avatar(_event), do: nil

  def slack_event_external?(%{metadata: %{"author_is_external" => true}}), do: true
  def slack_event_external?(_), do: false

  def slack_event_channel(%{metadata: %{"channel_name" => name} = metadata}) when is_binary(name) do
    "#{slack_app_label(metadata["slack_app"])} / ##{name}"
  end

  def slack_event_channel(_), do: ""

  def slack_reply_author(%{slack_user: %SlackUser{} = slack_user}), do: SlackUser.best_display_name(slack_user)

  def slack_reply_author(_reply), do: gettext("Unknown")

  def slack_reply_avatar(%{slack_user: %SlackUser{avatar_url: url}}) when is_binary(url) and url != "", do: url

  def slack_reply_avatar(_reply), do: nil

  def slack_reply_external?(%{slack_user: %SlackUser{is_external: true}}), do: true
  def slack_reply_external?(_reply), do: false

  def slack_channel_url(%{channel_id: channel_id}) when is_binary(channel_id) do
    "https://slack.com/app_redirect?channel=" <> channel_id
  end

  def slack_channel_label(%{slack_app: slack_app, channel_name: channel_name}) do
    "#{slack_app_label(slack_app)} / ##{channel_name}"
  end

  def slack_channel_option_value(%{slack_app: slack_app, slack_channel_id: channel_id}) do
    "#{slack_app}:#{channel_id}"
  end

  def slack_channel_option_label(option) do
    "#{slack_app_label(option.slack_app)} / ##{option.name}"
  end

  def slack_channel_none_option_value, do: "_none"

  def selected_slack_channel_value(nil), do: slack_channel_none_option_value()

  def selected_slack_channel_value(%{slack_app: slack_app, channel_id: channel_id}) do
    "#{slack_app}:#{channel_id}"
  end

  def slack_channel_select_label([]), do: gettext("No Slack channels available")
  def slack_channel_select_label(_options), do: gettext("Select a channel")

  def slack_channel_dropdown_label(value, _options) when value in [nil, "", "_none"], do: gettext("None")

  def slack_channel_dropdown_label(value, options) do
    case Enum.find(options, &(slack_channel_option_value(&1) == value)) do
      nil -> slack_channel_select_label(options)
      option -> slack_channel_option_label(option)
    end
  end

  def slack_app_label(:company), do: gettext("Company")
  def slack_app_label(:community), do: gettext("Community")
  def slack_app_label("company"), do: gettext("Company")
  def slack_app_label("community"), do: gettext("Community")
  def slack_app_label(_), do: gettext("Company")
end
