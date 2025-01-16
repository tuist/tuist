defmodule Tuist.Marketing.Newsletter.Issue do
  @moduledoc ~S"""
  This struct represents a newsletter issue. Each issue is a YAML file at `priv/marketing/newsletter/issues/*` and contains a set of standardized sections in Markdown. Those sections are converted into HTML and contained in this struct.
  """
  @enforce_keys [
    :date,
    :number,
    :title,
    :full_title,
    :body,
    :tools,
    :interview,
    :food_for_thought,
    :plain_html,
    :hero
  ]
  defstruct [
    :welcome_message,
    :date,
    :number,
    :title,
    :full_title,
    :body,
    :tools,
    :interview,
    :food_for_thought,
    :plain_html,
    :hero
  ]

  def build(_filename, attrs, body) do
    struct!(__MODULE__,
      welcome_message: attrs["welcome_message"],
      date: attrs["date"],
      number: attrs["number"],
      title: attrs["title"],
      full_title: "Swift Stories - Issue #{attrs["number"]} / #{attrs["title"]}",
      tools: attrs["tools"],
      interview: attrs["interview"],
      food_for_thought: attrs["food_for_thought"],
      plain_html: attrs["plain_html"],
      hero: attrs["hero"],
      body: body
    )
  end
end
