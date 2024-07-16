defmodule Tuist.Ops.DailySlackReportWorkerTest do
  use Tuist.DataCase, async: true
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures
  alias Tuist.CommandEventsFixtures
  alias Tuist.CommandEvents
  use Mimic

  test "generates and sends the report" do
    # Given
    Tuist.Time |> stub(:utc_now, fn -> ~U[2024-05-21 10:20:30Z] end)
    created_at = ~U[2024-05-20 10:20:30Z]
    user = AccountsFixtures.user_fixture(created_at: created_at) |> Repo.preload(:account)

    project =
      ProjectsFixtures.project_fixture(account_id: user.account.id, created_at: created_at)

    AccountsFixtures.organization_fixture(creator: user, created_at: created_at)

    CommandEventsFixtures.command_event_fixture(
      project_id: project.id,
      name: "generate",
      duration: 1500,
      created_at: created_at,
      remote_cache_target_hits: ["target1", "target2"]
    )

    CommandEvents.create_cache_event(%{
      project_id: project.id,
      name: "a",
      event_type: :download,
      size: 1000,
      hash: "hash-2",
      created_at: created_at
    })

    Tuist.Slack
    |> stub(:send_message, fn blocks ->
      assert blocks == [
               %{
                 type: "header",
                 text: %{type: "plain_text", text: "Daily report 21.5.2024 📈"}
               },
               %{
                 type: "context",
                 elements: [
                   %{
                     type: "plain_text",
                     text:
                       "Great things start small—believe in your vision and keep pushing forward."
                   }
                 ]
               },
               %{
                 type: "section",
                 text: %{
                   type: "plain_text",
                   text:
                     "The following data represents data from Monday to today, and its growth compared to the same weekday last week:\n"
                 }
               },
               %{
                 type: "rich_text",
                 elements: [
                   %{type: "rich_text_section", elements: []},
                   %{
                     type: "rich_text_list",
                     elements: [
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{type: "text", text: "👩‍💻 Users: ", style: %{bold: true}},
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{
                             type: "text",
                             text: "💼 Organizations: ",
                             style: %{bold: true}
                           },
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{type: "text", text: "⚙️ Projects: ", style: %{bold: true}},
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{type: "text", text: "📦 Cache events: ", style: %{bold: true}},
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       },
                       %{
                         type: "rich_text_section",
                         elements: [
                           %{
                             type: "text",
                             text: "▶️ Command events: ",
                             style: %{bold: true}
                           },
                           %{type: "text", text: "1 created (↑ 0.0%) | Total: 1\n"}
                         ]
                       }
                     ],
                     style: "bullet"
                   }
                 ]
               }
             ]

      :ok
    end)

    # When
    Tuist.Ops.DailySlackReportWorker.perform(%{})
  end
end
