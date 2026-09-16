defmodule Atlas.Support.Email do
  @moduledoc false

  import Swoosh.Email

  alias Atlas.Support.Attachments
  alias Atlas.Support.Markdown
  alias Atlas.Support.Message
  alias Atlas.Support.Thread
  alias Swoosh.Attachment

  def reply(%Thread{} = thread, %Message{} = message) do
    defaults = Application.get_env(:atlas, :support, [])
    from_name = Keyword.fetch!(defaults, :from_name)
    from_email = Keyword.fetch!(defaults, :from_email)

    new()
    |> from({from_name, from_email})
    |> to(recipients(message.to_emails))
    |> maybe_cc(message.cc_emails)
    |> reply_to(from_email)
    |> subject(reply_subject(thread.subject))
    |> text_body(Markdown.to_text(message.body))
    |> html_body(html_body(message.body))
    |> header("Message-ID", bracket(message.message_id))
    |> maybe_header("In-Reply-To", bracket(message.in_reply_to))
    |> maybe_header("References", references_header(message.references))
    |> add_attachments(message)
  end

  def chat_email_verification(%Thread{} = thread, confirmation_url) when is_binary(confirmation_url) do
    defaults = Application.get_env(:atlas, :support, [])
    from_name = Keyword.fetch!(defaults, :from_name)
    from_email = Keyword.fetch!(defaults, :from_email)

    body = """
    Confirm your email address to receive replies to your Tuist support chat.

    #{confirmation_url}

    If you did not start this chat, you can ignore this email.
    """

    new()
    |> from({from_name, from_email})
    |> to({"", thread.customer_email})
    |> reply_to(from_email)
    |> subject("Confirm your email for Tuist Support")
    |> text_body(body)
    |> html_body(body)
  end

  defp recipients(emails), do: Enum.map(emails, &{"", &1})
  defp maybe_cc(email, []), do: email
  defp maybe_cc(email, addresses), do: cc(email, recipients(addresses))
  defp maybe_header(email, _name, nil), do: email
  defp maybe_header(email, name, value), do: header(email, name, value)
  defp reply_subject(nil), do: "Re: Tuist support"

  defp reply_subject(subject) when is_binary(subject) do
    if String.starts_with?(String.downcase(subject), "re:"), do: subject, else: "Re: #{subject}"
  end

  defp bracket(nil), do: nil
  defp bracket(value), do: "<#{value}>"

  defp references_header(references) do
    case Enum.map_join(references, " ", &bracket/1) do
      "" -> nil
      value -> value
    end
  end

  defp html_body(body) do
    content = Markdown.to_html(body)

    """
    <!doctype html>
    <html>
      <body>
        #{content}
      </body>
    </html>
    """
  end

  defp add_attachments(email, message) do
    message.metadata
    |> Map.get("attachments", [])
    |> Enum.reduce_while({:ok, email}, fn attachment_metadata, {:ok, email} ->
      case Attachments.load(attachment_metadata) do
        {:ok, attachment} ->
          attached_email =
            attachment(
              email,
              Attachment.new({:data, attachment.body},
                filename: attachment.filename,
                content_type: attachment.content_type
              )
            )

          {:cont, {:ok, attached_email}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end
end
