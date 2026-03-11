defmodule TuistWeb.Storybook.Table do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Table

  def function, do: &Table.table/1
  def layout, do: :one_column

  def imports,
    do: [
      {Table,
       text_cell: 1,
       text_and_description_cell: 1,
       badge_cell: 1,
       status_badge_cell: 1,
       button_cell: 1,
       link_button_cell: 1,
       tag_cell: 1,
       time_cell: 1},
      {Noora.Button, button: 1},
      {Noora.Icon, chevron_left: 1, pencil: 1, trash: 1},
      {Noora.Badge, badge: 1}
    ]

  def variations do
    [
      %Variation{
        id: :cell_types,
        attributes: %{
          rows: [
            %{id: 1, label: "Row One"},
            %{id: 2, label: "Row Two"}
          ]
        },
        slots: [
          """
          <:col :let={i} label="Text">
            <.text_cell label={i.label} sublabel="(Internal)" icon="alert_circle" />
          </:col>
          <:col :let={i} label="Text and description">
            <.text_and_description_cell label={i.label} description="An internal identifier" icon="alert_circle" />
          </:col>
          <:col :let={i} label="Text and description with image">
            <.text_and_description_cell label={i.label} description="Look, an image!" secondary_description="So pretty.">
              <:image>
                <img src="/images/tuist_social.jpeg" />
              </:image>
            </.text_and_description_cell>
          </:col>
          <:col :let={i} label="Tag">
            <.tag_cell label={i.label} icon="category" />
          </:col>
          <:col :let={i} label="Badge">
            <.badge_cell label={i.label} color="warning" style="light-fill" />
          </:col>
          <:col :let={i} label="Status badge">
            <.status_badge_cell label={i.label} status="success" />
          </:col>
          <:col :let={i} label="Button">
            <.button_cell>
          <:button>
          <.button label={i.label} variant="secondary"/>
          </:button>
          </.button_cell>
          </:col>
          <:col :let={i} label="Button with multiple buttons">
            <.button_cell>
              <:button>
                <.button variant="secondary" icon_only><.pencil /></.button>
              </:button>
              <:button>
                <.button variant="secondary" icon_only><.trash /></.button>
              </:button>
            </.button_cell>
          </:col>
          <:col :let={i} label="Link button">
            <.link_button_cell label={i.label} variant="secondary" underline={true}>
              <:icon_left>
                <.chevron_left />
              </:icon_left>
            </.link_button_cell>
          </:col>
          <:col :let={i} label="Time">
            <.time_cell time={~U[2023-01-01 12:00:00Z]} />
          </:col>
          """
        ]
      },
      %Variation{
        id: :example,
        attributes: %{
          rows: [
            %{
              command: "test TuistKitAcceptanceTests",
              status: "Success",
              ran_by: "CI",
              duration: "5s",
              created_at: "2 hours ago"
            }
          ]
        },
        slots: [
          """
          <:col :let={i} label="Command">
            <.text_cell label={i.command} />
          </:col>
          <:col :let={i} label="Status">
            <.status_badge_cell label={i.status} status={String.downcase(i.status)} />
          </:col>
          <:col :let={i} label="Ran by">
            <.badge_cell label={i.ran_by} color="information" style="light-fill" />
          </:col>
          <:col :let={i} label="Duration" icon="square_rounded_arrow_down">
            <.text_cell label={i.duration} />
          </:col>
          <:col :let={i} label="Created at">
            <.text_cell sublabel={i.created_at} />
          </:col>
          """
        ]
      },
      %Variation{
        id: :expandable_rows,
        description: "Table with expandable rows showing additional details",
        attributes: %{
          rows: [
            %{
              id: "task-1",
              task: "GeneratedAssetSymbols.swift",
              hit: "Remote",
              type: "Clang",
              cache_key: "0-9wL-pE6ciuBQsAiC...",
              expandable: true,
              dependencies: [
                %{description: "CAS output swift dependencies: 0311864a9d4c1dsf1sa... (in target \"App\" from project \"App\")"},
                %{description: "CAS output swift dependencies: 0311864a9d4c1dsf1sa... (in target \"App\" from project \"App\")"}
              ]
            },
            %{
              id: "task-2",
              task: "CompileSwiftSources.swift",
              hit: "Local",
              type: "Swift",
              cache_key: "0-9wL-pE6ciuBQsAiC...",
              expandable: true,
              dependencies: []
            },
            %{
              id: "task-3",
              task: "LinkBinary",
              hit: "Missed",
              type: "Clang",
              cache_key: "0-213dadsdasdfaBOs...",
              expandable: false
            }
          ],
          row_expandable: {:eval, ~s|fn row -> Map.get(row, :expandable, false) end|},
          expanded_rows: ["task-1"]
        },
        slots: [
          """
          <:col :let={i} label="Task">
            <.text_cell label={i.task} />
          </:col>
          <:col :let={i} label="Hit">
            <.badge_cell
              label={i.hit}
              color={case i.hit do
                "Remote" -> "primary"
                "Local" -> "success"
                "Missed" -> "warning"
              end}
              style="light-fill"
            />
          </:col>
          <:expanded_content :let={row}>
            <div :for={dep <- row.dependencies} style="margin-bottom: 12px; padding: 12px; background-color: var(--color-neutral-background-primary); border-radius: 6px;">
              <div style="color: var(--color-neutral-text-secondary); font-size: 14px;">
                {dep.description}
              </div>
            </div>
          </:expanded_content>
          """
        ]
      }
    ]
  end
end
