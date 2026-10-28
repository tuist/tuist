defmodule Atlas.SupportInbox.Agents.ClassifierAgentEvalTest do
  @moduledoc """
  Runs the classifier against a hand-labeled fixture of real inbound
  emails and asserts recall/precision floors. Tagged `:external`
  because it makes real LLM calls — run it locally before landing
  changes to the agent prompt, tools, or model.

      mix test --only external test/atlas/support_inbox/agents/classifier_agent_eval_test.exs

  The recall floor on `action_needed=true` is the primary safety
  net: silencing a real support thread is the failure mode we care
  about most.
  """

  use ExUnit.Case, async: true

  alias Atlas.SupportInbox.Agents.ClassifierAgent

  @moduletag :external

  @fixture_path Path.expand("../fixtures/classifications.exs", __DIR__)

  @action_needed_recall_floor 0.95
  @overall_accuracy_floor 0.80

  test "classifier meets recall floor on action_needed=true across the fixture" do
    fixture = Code.eval_file(@fixture_path) |> elem(0)

    results =
      fixture
      |> Enum.map(fn entry ->
        input = %{
          from: entry.from,
          subject: entry.subject,
          body: nil,
          has_attachments: false
        }

        case ClassifierAgent.classify(input) do
          {:ok, decision} ->
            %{
              entry: entry,
              decision: decision,
              category_match: decision.category == entry.category,
              action_needed_match: decision.action_needed == entry.action_needed,
              urgency_match: decision.urgency == entry.urgency
            }

          {:error, reason} ->
            flunk("Classifier failed on #{entry.from} / #{entry.subject}: #{inspect(reason)}")
        end
      end)

    action_needed_entries = Enum.filter(results, & &1.entry.action_needed)
    recalled = Enum.count(action_needed_entries, & &1.decision.action_needed)
    total_action_needed = length(action_needed_entries)

    recall = if total_action_needed == 0, do: 1.0, else: recalled / total_action_needed

    total_correct = Enum.count(results, & &1.action_needed_match)
    accuracy = total_correct / length(results)

    misses =
      results
      |> Enum.filter(fn r -> r.entry.action_needed and not r.decision.action_needed end)
      |> Enum.map_join("\n", fn r -> "  #{r.entry.from} — #{r.entry.subject}" end)

    IO.puts("""

    ClassifierAgent eval:
      action_needed recall:   #{Float.round(recall * 100, 1)}% (#{recalled}/#{total_action_needed})
      action_needed accuracy: #{Float.round(accuracy * 100, 1)}% (#{total_correct}/#{length(results)})
    #{if misses == "", do: "", else: "  Missed action_needed=true entries:\n" <> misses}
    """)

    assert recall >= @action_needed_recall_floor,
           "action_needed recall #{recall} below floor #{@action_needed_recall_floor}"

    assert accuracy >= @overall_accuracy_floor,
           "action_needed accuracy #{accuracy} below floor #{@overall_accuracy_floor}"
  end
end
