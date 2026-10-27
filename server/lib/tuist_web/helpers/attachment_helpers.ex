defmodule TuistWeb.Helpers.AttachmentHelpers do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  def attachment_type(file_name) do
    ext = file_name |> String.downcase() |> Path.extname()

    cond do
      ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"] -> :image
      ext in [".txt"] -> :text
      ext in [".log"] -> :log
      ext in [".json"] -> :json
      ext in [".xml"] -> :xml
      ext in [".csv"] -> :csv
      ext in [".ips"] -> :ips
      true -> :file
    end
  end

  def text_attachment_type?(type), do: type in [:text, :log, :json, :xml, :csv]

  def attachment_type_label(:image), do: dgettext("dashboard_tests", "Image")
  def attachment_type_label(:text), do: dgettext("dashboard_tests", "Text File")
  def attachment_type_label(:log), do: dgettext("dashboard_tests", "Log File")
  def attachment_type_label(:json), do: "JSON"
  def attachment_type_label(:xml), do: "XML"
  def attachment_type_label(:csv), do: "CSV"
  def attachment_type_label(:ips), do: dgettext("dashboard_tests", "Crash Report")
  def attachment_type_label(:file), do: dgettext("dashboard_tests", "File")
end
