import Ecto.Query, only: [from: 2]

alias Tuist.Accounts
alias Tuist.Billing.Subscription
alias Tuist.CommandEvents
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.Repo
alias Tuist.Runs.Build
alias Tuist.Xcode

# Stubs
email = "tuistrocks@tuist.io"
password = "tuistrocks"

account =
  Accounts.get_user_by_email(email)

account =
  if is_nil(account) do
    {:ok, account} =
      Accounts.create_user(email,
        password: password,
        confirmed_at: NaiveDateTime.utc_now(),
        setup_billing: false,
        customer_id: "cus_RFlTyvSVonyndv"
      )

    %Subscription{}
    |> Subscription.create_changeset(%{
      plan: :pro,
      subscription_id: "sub_1QNEs2LWue9IBlPSsKtuPQ5L",
      status: "active",
      account_id: account.id,
      default_payment_method: "pmc_1QNBBVLWue9IBlPSH2tnx4hH"
    })
    |> Repo.insert!()

    account
  else
    account
  end

user = Accounts.get_user_by_email(email)

organization =
  if Accounts.get_organization_by_handle("tuist") do
    Accounts.get_organization_by_handle("tuist")
  else
    organization =
      Accounts.create_organization!(%{name: "tuist", creator: user}, setup_billing: false)

    organization.account
  end

_public_project =
  case "tuist/public" |> Projects.get_project_by_slug() |> dbg() do
    {:ok, %Project{} = project} ->
      project

    {:error, _} ->
      Projects.create_project(%{name: "public", account: %{id: organization.id}},
        visibility: :public
      )
  end

ios_app_with_frameworks_project =
  case Projects.get_project_by_slug("tuist/ios_app_with_frameworks") do
    {:ok, project} ->
      project

    {:error, _} ->
      Projects.create_project!(%{
        name: "ios_app_with_frameworks",
        account: %{id: organization.id}
      })
  end

_org_project =
  Projects.get_project_by_slug("tuist/tuist") ||
    Projects.create_project!(%{name: "tuist", account: %{id: organization.id}})

builds =
  Enum.map(1..2000, fn _ ->
    status = Enum.random([:success, :failure])
    is_ci = Enum.random([true, false])
    account_id = if is_ci, do: organization.id, else: user.account.id

    inserted_at =
      DateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..400)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59)
        )
      )

    %{
      id: UUIDv7.generate(),
      duration: Enum.random(10_000..100_000),
      macos_version: "11.2.3",
      xcode_version: "12.4",
      is_ci: is_ci,
      model_identifier: "Mac15,6",
      project_id: ios_app_with_frameworks_project.id,
      account_id: account_id,
      inserted_at: inserted_at,
      status: status
    }
  end)

Repo.insert_all(Build, builds)

for _event <- 1..8000 do
  names = ["test", "cache", "generate"]
  name = Enum.random(names)
  status = Enum.random([:success, :failure])
  is_ci = Enum.random([true, false])
  user_id = if is_ci, do: nil, else: user.id

  cacheable_targets = [
    "TargetOne",
    "TargetTwo",
    "TargetThree",
    "TargetFour",
    "TargetFive",
    "TargetSix",
    "TargetSeven",
    "TargetEight",
    "TargetNine",
    "TargetTen",
    "TargetEleven",
    "TargetTwelve",
    "TargetThirteen",
    "TargetFourteen",
    "TargetFifteen"
  ]

  remote_cache_target_hits = Enum.take(cacheable_targets, Enum.random(0..14))

  local_cache_target_hits =
    cacheable_targets
    |> Enum.reverse()
    |> Enum.take(Enum.random(0..(14 - length(remote_cache_target_hits))))

  test_targets =
    if name == "test" do
      [
        "TestTargetOne",
        "TestTargetTwo",
        "TestTargetThree",
        "TestTargetFour",
        "TestTargetFive",
        "TestTargetSix",
        "TestTargetSeven",
        "TestTargetEight",
        "TestTargetNine",
        "TestTargetTen",
        "TestTargetEleven",
        "TestTargetTwelve",
        "TestTargetThirteen",
        "TestTargetFourteen",
        "TestTargetFifteen"
      ]
    else
      []
    end

  remote_test_target_hits = Enum.take(test_targets, Enum.random(0..14))

  local_test_target_hits =
    test_targets
    |> Enum.reverse()
    |> Enum.take(Enum.random(0..(14 - length(remote_test_target_hits))))

  created_at =
    NaiveDateTime.new!(
      Date.add(DateTime.utc_now(), -Enum.random(0..400)),
      Time.new!(
        Enum.random(0..23),
        Enum.random(0..59),
        Enum.random(0..59),
        Enum.random(0..999_999)
      )
    )

  ran_at = created_at

  CommandEvents.create_command_event(%{
    name: name,
    duration: Enum.random(10_000..100_000),
    tuist_version: "4.1.0",
    project_id: ios_app_with_frameworks_project.id,
    cacheable_targets: cacheable_targets,
    local_cache_target_hits: local_cache_target_hits,
    remote_cache_target_hits: remote_cache_target_hits,
    test_targets: test_targets,
    local_test_target_hits: local_test_target_hits,
    remote_test_target_hits: remote_test_target_hits,
    swift_version: "5.2",
    macos_version: "10.15",
    subcommand: "",
    command_arguments: [],
    is_ci: is_ci,
    user_id: user_id,
    client_id: "client-id",
    status: status,
    error_message: nil,
    preview_id: nil,
    git_ref: nil,
    git_commit_sha: nil,
    git_branch: nil,
    created_at:
      NaiveDateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..400)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59),
          Enum.random(0..999_999)
        )
      ),
    ran_at: ran_at
  })
end

test_command_events = Tuist.Repo.all(from(c in CommandEvents.Event, where: c.name == "test"))

test_cases =
  Enum.map(1..100, fn index ->
    name = "test#{index}"

    module_name =
      Enum.random(["ModuleOne", "ModuleTwo", "ModuleThree", "ModuleFour", "ModuleFive"])

    identifier = "#{module_name}/#{name}"
    test_case = CommandEvents.get_test_case_by_identifier(identifier)

    command_event = test_command_events |> Enum.random() |> Repo.preload(:xcode_graph)

    test_case =
      if is_nil(test_case) do
        CommandEvents.create_test_case(
          %{
            name: name,
            module_name: module_name,
            identifier: identifier,
            project_identifier: "AppTests/AppTests.xcodeproj",
            project_id: ios_app_with_frameworks_project.id
          },
          flaky: Enum.random([true, false, false, false, false])
        )
      else
        test_case
      end

    graph =
      if is_nil(command_event.xcode_graph) do
        {:ok, graph} =
          Xcode.create_xcode_graph(%{
            command_event: command_event,
            xcode_graph: %{
              name: "Graph",
              projects: [
                %{
                  "name" => name,
                  "path" => module_name,
                  "targets" => [
                    %{
                      "name" => "target-#{System.unique_integer([:positive])}",
                      "binary_cache_metadata" => %{
                        "hash" => "binary-cache-hash-#{System.unique_integer([:positive])}",
                        "hit" => "miss"
                      }
                    }
                  ]
                }
              ]
            }
          })

        graph
      else
        command_event.xcode_graph
      end

    graph = Repo.preload(graph, xcode_projects: [:xcode_targets])

    for _ <- 1..100 do
      CommandEvents.create_test_case_run(
        %{
          status: Enum.random([:success, :failure]),
          test_case_id: test_case.id,
          command_event_id: command_event.id,
          xcode_target_id:
            graph.xcode_projects
            |> List.first()
            |> Map.get(:xcode_targets)
            |> Enum.random()
            |> Map.get(:id)
        },
        flaky: Enum.random([test_case.flaky, false, false, false])
      )
    end
  end)
