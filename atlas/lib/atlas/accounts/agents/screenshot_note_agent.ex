defmodule Atlas.Accounts.Agents.ScreenshotNoteAgent do
  @moduledoc """
  A Condukt-based agent that turns screenshots into a sales-flavored
  account note.
  """

  use Condukt

  alias Atlas.Agents.Sessions
  alias Atlas.Agents.StyleGuide
  alias Atlas.LLMs.Runner

  @impl true
  def tools, do: []

  @impl true
  def system_prompt do
    """
    You extract sales-relevant context from screenshots and produce a short
    note (2-5 sentences, plain prose) that a sales person can drop into the
    timeline of a customer account.

    The screenshots may show a chat conversation, a meeting recap, an email
    thread, a CRM entry, a call transcript, a dashboard, or a document.
    If there are multiple screenshots, combine their context into one
    coherent note and preserve the visible sequence when it matters.

    Capture, when present:
    - What the conversation or page is about
    - Who is involved (named people, roles, companies)
    - Deal stage signals: blockers, objections, asks, commitments, dates
    - Pricing, seat counts, plan, contract or renewal hints
    - Competitor or alternative-tool mentions
    - Concrete commitments, with owner and due date if visible

    Be factual and grounded in what is visible. Do not invent names, numbers,
    or dates. If the screenshot is illegible or off-topic, say so briefly.
    Do not use markdown headers or bullet points. Write in plain prose suitable
    for a timeline note.

    #{StyleGuide.prose_rules()}
    """
  end

  @doc """
  Drafts a note from a base64-encoded screenshot.

  `account_context` is an optional map (e.g. `%{name: "Acme"}`) used to give
  the model a hint about which account this is for.

  Returns `{:ok, note_text}` or `{:error, reason}`.
  """
  def draft_note(base64_image, media_type, account_context \\ nil) do
    draft_note_from_screenshots([%{data: base64_image, media_type: media_type}], account_context)
  end

  @doc """
  Drafts a note from one or more base64-encoded screenshots.
  """
  def draft_note_from_screenshots(screenshots, account_context \\ nil)

  def draft_note_from_screenshots([], _account_context), do: {:error, :no_screenshots}

  def draft_note_from_screenshots(screenshots, account_context) when is_list(screenshots) do
    with {:ok, llm} <- Runner.fetch_config() do
      images = Enum.map(screenshots, &image_from_screenshot/1)

      Sessions.run(
        __MODULE__,
        build_prompt(account_context, length(images)),
        Runner.client_opts(llm) ++ [images: images, max_turns: 1, account_id: account_id_from(account_context)]
      )
    end
  end

  defp image_from_screenshot(%{data: data, media_type: media_type}) do
    %{type: :base64, media_type: media_type, data: data}
  end

  defp image_from_screenshot(%{"data" => data, "media_type" => media_type}) do
    %{type: :base64, media_type: media_type, data: data}
  end

  defp account_id_from(%{id: id}) when is_binary(id), do: id
  defp account_id_from(_), do: nil

  defp build_prompt(nil, 1) do
    "Draft the timeline note from the attached screenshot."
  end

  defp build_prompt(nil, count) do
    "Draft the timeline note from the #{count} attached screenshots."
  end

  defp build_prompt(%{name: account_name, contact_name: contact_name}, 1)
       when is_binary(account_name) and account_name != "" and is_binary(contact_name) and contact_name != "" do
    "Draft the timeline note from the attached screenshot. The contact is #{contact_name} at #{account_name}."
  end

  defp build_prompt(%{name: account_name, contact_name: contact_name}, count)
       when is_binary(account_name) and account_name != "" and is_binary(contact_name) and contact_name != "" do
    "Draft the timeline note from the #{count} attached screenshots. The contact is #{contact_name} at #{account_name}."
  end

  defp build_prompt(%{name: name}, 1) when is_binary(name) and name != "" do
    "Draft the timeline note from the attached screenshot. The account is #{name}."
  end

  defp build_prompt(%{name: name}, count) when is_binary(name) and name != "" do
    "Draft the timeline note from the #{count} attached screenshots. The account is #{name}."
  end

  defp build_prompt(_, count), do: build_prompt(nil, count)
end
