defmodule Tuist.Marketing.Newsletter.IssueParser do
  @moduledoc ~S"""
  This module is responsible for parsing changelog entries from markdown files.
  """

  @plain_html_template Solid.parse!(~s"""
                       <h1>{{ full_title }}</h1>
                       <h2>Welcome to issue {{ number }}</h2>
                       <article>
                          {%- if welcome_message -%}
                          <p>
                            {{ welcome_message | lstrip | rstrip }}
                          </p>
                          {%- endif -%}
                          {{ body | lstrip | rstrip }}
                       </article>
                       <article>
                          <h2>Tools & sites</h2>
                          {% for tool in tools %}
                          <section>
                            <h3><a href="{{ tool.link }}" target="__blank">{{ tool.title }}</a></h3>
                            <p>{{ tool.subtitle }}</p>
                            {{ tool.description | lstrip | rstrip }}
                          </section>
                          {% endfor %}
                       </article>
                       <article>
                          <h2>Worthy Five: {{ interview.interviewee }}</h2>
                          {{ interview.interviewee_intro | lstrip | rstrip }}
                          <img src="{{ interview.interviewee_avatar_url }}" alt="{{ interview.interviewee }}" />
                          <small>{{ interview.interviewee_role }} </small>
                          {% for question in interview.questions %}
                          <h3>{{ question.question }}</h3>
                          {{ question.answer | lstrip | rstrip }}
                          {% endfor %}
                       </article>
                       <article>
                          <h2>Food for thought</h2>
                          {% for item in food_for_thought %}
                          <section>
                            <h3><a href="{{ item.link }}" target="__blank">{{ item.title }}</a></h3>
                            {{ item.description | lstrip | rstrip }}
                          </section>
                          {% endfor %}
                       </article>

                       <footer>
                       <h2>Enjoyed it? Share it</h2>

                       <p>Swift Stories is a newsletter brought to you by the people behind Tuist. We love cross-polinating ideas from and to the Swift ecosystem and building tools that make developers' lives easier. If you want to share ideas for future issues, you can do so in our <a href="#{Tuist.Environment.get_url(:forum)}">community forum</a>. If you like this newsletter, you can support us by sharing it with your friends and colleagues.</p>

                       <p>Stay in touch: <a href="#{Tuist.Environment.get_url(:forum)}">Community</a>, <a href="#{Tuist.Environment.get_url(:mastodon)}">Mastodon</a>, <a href="#{Tuist.Environment.get_url(:github)}">GitHub</a>, and <a href="#{Tuist.Environment.get_url(:slack)}">Slack</a></p>

                       <p><a href="#{Tuist.Environment.app_url(path: "/newsletter")}">Subscribe to newsletter</a></p>

                       <p><a href="#{Tuist.Environment.app_url(path: "/terms")}">Terms of service</a> | <a href="#{Tuist.Environment.app_url(path: "/privacy")}">Privacy policy</a>
                       </footer>
                       """)

  def parse(path, contents) do
    issue_number = path |> Path.basename() |> String.replace(".yml", "") |> String.to_integer()

    attrs =
      contents
      |> YamlElixir.read_from_string!()
      |> Map.replace_lazy("date", &map_date/1)
      |> Map.replace_lazy("body", &md_to_html/1)
      |> Map.put("number", issue_number)
      |> Map.replace_lazy("hero", &map_hero/1)
      |> Map.replace_lazy("tools", &map_tools/1)
      |> Map.replace_lazy("interview", &map_interview/1)
      |> Map.replace_lazy("food_for_thought", &food_for_thought/1)

    attrs = Map.put(attrs, "plain_html", plain_html(attrs))

    {attrs, attrs["body"]}
  end

  defp map_date(date_string) do
    date_string |> Date.from_iso8601!() |> Timex.to_datetime("Etc/UTC")
  end

  defp map_tools(tools) do
    Enum.map(tools, fn tool ->
      Map.replace_lazy(tool, "description", &md_to_html/1)
    end)
  end

  defp food_for_thought(food_for_thought) do
    Enum.map(food_for_thought, fn food ->
      Map.replace_lazy(food, "description", &md_to_html/1)
    end)
  end

  defp map_interview(interview) do
    interview
    |> Map.replace_lazy("interviewee_intro", &md_to_html/1)
    |> Map.replace_lazy("questions", fn questions ->
      Enum.map(questions, fn %{"question" => question, "answer" => answer} ->
        %{"question" => question, "answer" => md_to_html(answer)}
      end)
    end)
  end

  defp md_to_html(md, opts \\ []) do
    a_color = Keyword.get(opts, :a_color, "#622ed4")

    # Gmail doesn't support styling through <style></style>, so when converting markdown to HTML, we have to apply the right
    # styling at the element level by using "style" attributes.
    md
    |> MDEx.to_html!(parse: [smart: false], render: [unsafe: true])
    |> Floki.parse_fragment!()
    |> style_email_nodes(a_color)
    |> Floki.raw_html()
  end

  defp style_email_nodes(nodes, a_color) do
    Enum.map(nodes, &style_email_node(&1, a_color, false))
  end

  defp style_email_node({"pre", attrs, children}, a_color, _inside_pre) do
    {"pre", attrs, Enum.map(children, &style_email_node(&1, a_color, true))}
  end

  defp style_email_node({"a", attrs, children}, a_color, inside_pre) do
    {"a", put_attribute(attrs, "style", "color: #{a_color};"),
     Enum.map(children, &style_email_node(&1, a_color, inside_pre))}
  end

  defp style_email_node({"blockquote", attrs, children}, a_color, inside_pre) do
    {"blockquote", put_attribute(attrs, "style", "font-style: italic;"),
     Enum.map(children, &style_email_node(&1, a_color, inside_pre))}
  end

  defp style_email_node({"code", attrs, children}, a_color, false) do
    {"code", put_attribute(attrs, "class", "inline"), Enum.map(children, &style_email_node(&1, a_color, false))}
  end

  defp style_email_node({tag, attrs, children}, a_color, inside_pre) do
    {tag, attrs, Enum.map(children, &style_email_node(&1, a_color, inside_pre))}
  end

  defp style_email_node(text, _a_color, false) when is_binary(text), do: String.replace(text, "\n", " ")
  defp style_email_node(node, _a_color, _inside_pre), do: node

  defp put_attribute(attrs, name, value) do
    case List.keytake(attrs, name, 0) do
      {{^name, existing_value}, remaining_attrs} ->
        [{name, "#{value} #{existing_value}"} | remaining_attrs]

      nil ->
        [{name, value} | attrs]
    end
  end

  defp map_hero(hero) do
    Map.replace_lazy(hero, "subtitle", fn subtitle_md ->
      md_to_html(subtitle_md, a_color: "#622ed4")
    end)
  end

  # The .heex format is designed for the Phoenix.LiveView.Engine to track changes
  # which is not a need for this use case.
  def plain_html(attrs) do
    attrs = Map.put(attrs, "date_string", attrs |> Map.fetch!("date") |> Timex.format!("{Mshort} {D}, {YYYY}"))

    @plain_html_template |> Solid.render!(attrs) |> to_string()
  end
end
