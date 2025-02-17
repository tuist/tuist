defmodule TuistWeb.Storybook.Table do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Table.table/1

  def imports,
    do: [
      {TuistWeb.Noora.Table,
       text_cell: 1,
       text_and_description_cell: 1,
       badge_cell: 1,
       status_badge_cell: 1,
       button_cell: 1},
      {TuistWeb.Noora.Button, button: 1},
      {TuistWeb.Noora.Icon, pencil: 1, trash: 1}
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
            <.text_and_description_cell label={i.label} description="Look, an image!">
              <:image>
                <img src="/images/tuist_social.jpeg" />
              </:image>
            </.text_and_description_cell>
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
      }
    ]
  end
end
