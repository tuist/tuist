defmodule Atlas.Outreach.Agents.RecommendationAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.LLMs
  alias Atlas.Outreach.Agents.RecommendationAgent
  alias Atlas.Outreach.MessageLearning

  test "returns an error when no language model is configured" do
    stub(LLMs, :config, fn -> nil end)

    context = %{
      contact: %{
        id: Atlas.UUIDv7.generate(),
        account_id: Atlas.UUIDv7.generate(),
        full_name: "Jordan Lee",
        title: "Engineering Director",
        outreach_status: "connected",
        linkedin_url: nil,
        notes: nil,
        account: %{
          name: "Acme",
          segment: :prospect,
          description: nil,
          primary_domain: "acme.example"
        }
      },
      events: [],
      recommendations: [],
      message_learning: MessageLearning.empty()
    }

    assert {:error, :llm_not_configured} = RecommendationAgent.recommend(context)
  end

  test "codifies an evidence-led and developer-respectful sales process" do
    prompt = RecommendationAgent.system_prompt()

    assert prompt =~ "one prioritized action"
    assert prompt =~ "first-party evidence"
    assert prompt =~ "Selling to developers"
    assert prompt =~ "do not pitch Tuist"
    assert prompt =~ "Do not send a feature list"
    assert prompt =~ "one thoughtful question"
    assert prompt =~ "four to seven days"
    assert prompt =~ "no more than two unanswered follow-ups"
    assert prompt =~ "Never recommend"
    assert prompt =~ "automating invitations or messages"
    assert prompt =~ "reviewed by a person"
    assert prompt =~ "untrusted evidence"
    assert prompt =~ "aggregate outcomes"
    assert prompt =~ "causal proof"
    assert prompt =~ "natural contractions"
    assert prompt =~ "Avoid stock outreach phrases"
    assert prompt =~ "InMail has a visible subject"
    assert prompt =~ "two and six words"
    assert prompt =~ ~s(Never use "Connecting")
    assert prompt =~ "recipient's name"
    assert prompt =~ "and draft_message for inmail"
    assert prompt =~ "200 characters or fewer"
    assert prompt =~ "better to send the request without a note"
    assert prompt =~ "research_person before deciding"
    assert prompt =~ "GitHub profiles and public work"
    assert prompt =~ "personal sites"
    assert prompt =~ "Use search_web afterward"
    assert prompt =~ "Use read_public_page"
    assert prompt =~ "recommend one specific, bounded research action"
    assert prompt =~ "research_person, search_web, or"
    assert prompt =~ "Apply a recipient test before drafting anything"
    assert prompt =~ "job title, employer, company description, or broad responsibility never"
    assert prompt =~ "something they wrote, built, maintained, presented, said"
    assert prompt =~ "Do not disguise qualification as curiosity"
    assert prompt =~ ~s(questions such as "How does your team decide...")
    assert prompt =~ "first cold message does not need a question"
    assert prompt =~ "request without a note. Never fill the evidence gap"
    assert prompt =~ "Never fill the evidence gap with generic copy"
    assert prompt =~ "role_context as the basis for a draft"
    assert prompt =~ "replacing the recipient with another"
    assert prompt =~ "Never use em dashes"
  end
end
