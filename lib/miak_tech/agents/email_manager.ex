defmodule MiakTech.Agent.EmailManager do
  use GenServer

  alias MiakTech.{Telegram, Windmill}

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def init(_), do: {:ok, %{}}

  def check_emails,
    do: GenServer.call(__MODULE__, :check_emails, 120_000)

  def reply_email(email_id, body),
    do: GenServer.call(__MODULE__, {:reply_email, email_id, body}, 60_000)

  def move_to_gulp(email_id),
    do: GenServer.call(__MODULE__, {:move_to_gulp, email_id}, 60_000)

  def handle_message(chat_id, text),
    do: GenServer.cast(__MODULE__, {:message, chat_id, text})

  def handle_cast({:message, chat_id, text}, state) do
    lower = String.downcase(text)

    cond do
      String.contains?(lower, "check email") ->
        Task.start(fn ->
          classified = check_emails()
          gulp_emails = for {e, :gulp} <- classified, do: e
          project_emails = for {e, :project} <- classified, do: e
          other_count = length(for {_, :other} <- classified, do: true)

          Telegram.send_message(
            chat_id,
            "*Jordan: Email check complete*\n" <>
              "Gulp: #{length(gulp_emails)} | Project leads: #{length(project_emails)} | Other: #{other_count}"
          )

          Enum.each(gulp_emails, fn email ->
            move_to_gulp(email["id"])
            Telegram.send_message(chat_id, "_Moved to Gulp folder: #{email["subject"]}_")
          end)

          Enum.each(project_emails, fn email ->
            Telegram.send_message(
              chat_id,
              "_Found project email: #{email["subject"]} — passing to CTO..._"
            )

            MiakTech.Agent.CTO.handle_email(chat_id, email)
          end)
        end)

        {:noreply, state}

      String.contains?(lower, "send email") ->
        Task.start(fn ->
          parsed = parse_send_command(text)

          if parsed[:to] && parsed[:subject] && parsed[:body] do
            Telegram.send_message(chat_id, "_Jordan is sending email..._")

            result =
              Windmill.run("u/ammad/mail/ms_graph_tool", %{
                action: "send_email",
                to_email: parsed[:to],
                subject: parsed[:subject],
                body_text: parsed[:body]
              })

            if result["status"] == "sent" do
              Telegram.send_message(
                chat_id,
                "*Jordan: Email sent*\n" <>
                  "To: #{parsed[:to]}\nSubject: #{parsed[:subject]}"
              )
            else
              Telegram.send_message(chat_id, "_Jordan: Failed to send email._")
            end
          else
            Telegram.send_message(
              chat_id,
              "_Jordan here. To send an email use this format:_\n" <>
                "`jordan send email to: x@x.com subject: Hello body: Your message here`"
            )
          end
        end)

        {:noreply, state}

      true ->
        Telegram.send_message(
          chat_id,
          "*Jordan here.* I can:\n" <>
            "- `jordan check email` — sort and classify emails\n" <>
            "- `jordan send email to: x@x.com subject: X body: X` — send an email"
        )

        {:noreply, state}
    end
  end

  def handle_call(:check_emails, _from, state) do
    result = Windmill.run("u/ammad/mail/ms_graph_tool", %{action: "list_unread", top: 20})
    emails = result["messages"] || []

    classified =
      Enum.map(emails, fn email ->
        from = ((email["from"] || %{})["address"] || "") |> String.downcase()
        subject = (email["subject"] || "") |> String.downcase()

        is_gulp =
          String.contains?(from, "gulp") or
            String.contains?(subject, "gulp") or
            String.contains?(from, "randstad")

        cond do
          is_gulp -> {email, :gulp}
          from == "ammadkhan@msn.com" -> {email, :project}
          true -> {email, :other}
        end
      end)

    {:reply, classified, state}
  end

  def handle_call({:reply_email, email_id, body}, _from, state) do
    result =
      Windmill.run("u/ammad/mail/ms_graph_tool", %{
        action: "reply_email",
        email_id: email_id,
        reply_body: body
      })

    {:reply, result, state}
  end

  def handle_call({:move_to_gulp, email_id}, _from, state) do
    folders_result =
      Windmill.run("u/ammad/mail/ms_graph_tool", %{
        action: "list_inbox_child_folders",
        top: 50
      })

    folders = folders_result["folders"] || []

    existing =
      Enum.find(folders, fn f ->
        String.downcase(f["display_name"] || "") == "gulp"
      end)

    folder_id =
      if existing do
        existing["id"]
      else
        created =
          Windmill.run("u/ammad/mail/ms_graph_tool", %{
            action: "create_folder",
            folder_name: "Gulp"
          })

        created["folder"]["id"]
      end

    Windmill.run("u/ammad/mail/ms_graph_tool", %{
      action: "move_email",
      email_id: email_id,
      destination_folder_id: folder_id
    })

    {:reply, :ok, state}
  end

  defp parse_send_command(text) do
    %{}
    |> put_if_matched(text, :to, ~r/to:\s*([^\s]+@[^\s]+)/i)
    |> put_if_matched(text, :subject, ~r/subject:\s*(.+?)(?=\s+body:)/i)
    |> put_if_matched(text, :body, ~r/body:\s*(.+)/is)
  end

  defp put_if_matched(map, text, key, regex) do
    case Regex.run(regex, text) do
      [_, value] -> Map.put(map, key, String.trim(value))
      _ -> map
    end
  end
end
