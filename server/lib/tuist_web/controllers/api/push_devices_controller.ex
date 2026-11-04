defmodule TuistWeb.API.PushDevicesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Push
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistWeb.RenderAPIErrorPlug
  )

  plug TuistWeb.Plugs.PushAppSessionPlug

  tags ["Push devices"]

  @installation_id [
    in: :path,
    type: :string,
    required: true,
    description: "The client-generated lowercase UUID that identifies this app installation."
  ]

  operation(:update,
    summary: "Registers this app installation for push notifications",
    description:
      "Associates the installation and its platform push token with the signed-in user. Only native app OAuth sessions can register. The registration lasts while that sign-in remains active.",
    operation_id: "registerPushDevice",
    parameters: [installation_id: @installation_id],
    request_body:
      {"Push device", "application/json",
       %Schema{
         type: :object,
         additionalProperties: false,
         properties: %{
           platform: %Schema{type: :string, enum: ["ios", "android"], description: "The device platform."},
           token: %Schema{
             type: :string,
             description: "The APNs device token (hex) on iOS or the FCM registration token on Android."
           },
           environment: %Schema{
             type: :string,
             enum: ["sandbox", "production"],
             description: "The APNs environment. Android is always production."
           },
           name: %Schema{
             type: :string,
             maxLength: 200,
             description: "The device model shown in the user's device list, for example iPhone 17 Pro."
           }
         },
         required: [:platform, :token, :environment]
       }},
    responses: %{
      ok:
        {"The installation is registered", "application/json",
         %Schema{
           type: :object,
           properties: %{registration_id: %Schema{type: :string, description: "The server registration ID."}},
           required: [:registration_id]
         }},
      bad_request: {"The device or installation ID is invalid", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"Only native app OAuth sessions can register push devices", "application/json", Error},
      conflict: {"The installation belongs to another user or registration", "application/json", Error},
      gone:
        {"The installation ID can no longer be registered", "application/json",
         %Schema{
           type: :object,
           properties: %{
             message: %Schema{type: :string},
             reason: %Schema{
               type: :string,
               description:
                 "`retired`: generate a new installation ID and retry. `removed`: the user removed this device from their device list; keep notifications off on this device until the user turns them back on, then use a new installation ID."
             }
           },
           required: [:message, :reason]
         }}
    }
  )

  operation(:index,
    summary: "Lists the signed-in user's push devices",
    operation_id: "listPushDevices",
    responses: %{
      ok:
        {"The user's devices", "application/json",
         %Schema{
           type: :object,
           properties: %{
             devices: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   registration_id: %Schema{type: :string},
                   installation_id: %Schema{type: :string},
                   platform: %Schema{type: :string, description: "ios or android"},
                   name: %Schema{type: :string, nullable: true},
                   registered_at: %Schema{type: :string, format: :"date-time"},
                   last_seen_at: %Schema{type: :string, format: :"date-time"}
                 },
                 required: [:registration_id, :installation_id, :platform, :registered_at, :last_seen_at]
               }
             }
           },
           required: [:devices]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"Only native app OAuth sessions can list push devices", "application/json", Error}
    }
  )

  def index(conn, _params) do
    devices =
      conn.assigns.push_user.id
      |> Push.live_installations()
      |> Enum.map(fn installation ->
        %{
          registration_id: installation.id,
          installation_id: installation.installation_id,
          platform: installation.platform,
          name: installation.device_name,
          registered_at: installation.inserted_at,
          last_seen_at: installation.last_registered_at
        }
      end)

    json(conn, %{devices: devices})
  end

  def update(%{path_params: %{"installation_id" => installation_id}, body_params: device} = conn, _params) do
    case Push.register(conn.assigns.push_user, conn.assigns.push_session, installation_id, device) do
      {:ok, installation} -> json(conn, %{registration_id: installation.id})
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:delete,
    summary: "Unregisters this app installation from push notifications",
    description:
      "Retires the installation if it belongs to the signed-in user. The installation ID cannot be registered again.",
    operation_id: "unregisterPushDevice",
    parameters: [installation_id: @installation_id],
    responses: %{
      no_content: "The installation is unregistered",
      bad_request: {"The installation ID is invalid", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"Only native app OAuth sessions can unregister push devices", "application/json", Error}
    }
  )

  def delete(%{path_params: %{"installation_id" => installation_id}} = conn, _params) do
    case Push.unregister(conn.assigns.push_user, installation_id) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  operation(:remove,
    summary: "Removes one of the signed-in user's devices",
    description:
      "Stops notifications to the device. When that device next refreshes its registration it learns it was removed and keeps notifications off until its user turns them back on.",
    operation_id: "removePushDevice",
    parameters: [
      registration_id: [in: :path, type: :string, required: true, description: "The device's registration ID."]
    ],
    responses: %{
      no_content: "The device is removed",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"Only native app OAuth sessions can remove push devices", "application/json", Error}
    }
  )

  def remove(%{path_params: %{"registration_id" => registration_id}} = conn, _params) do
    :ok = Push.remove_device(conn.assigns.push_user, registration_id)
    send_resp(conn, :no_content, "")
  end

  defp error(conn, :invalid), do: conn |> put_status(:bad_request) |> json(%{message: "Invalid push device."})

  defp error(conn, :conflict),
    do: conn |> put_status(:conflict) |> json(%{message: "The installation conflicts with another registration."})

  defp error(conn, :retired),
    do:
      conn
      |> put_status(:gone)
      |> json(%{message: "The installation was retired. Use a new installation ID.", reason: "retired"})

  defp error(conn, :removed),
    do: conn |> put_status(:gone) |> json(%{message: "This device was removed from your device list.", reason: "removed"})
end
