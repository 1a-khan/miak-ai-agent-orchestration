defmodule MiakTech.Agent.CTO do
  use GenServer

  alias MiakTech.{OpenAI, Telegram, DB}
  alias MiakTech.{Agent.EmailManager, Department.IT}

  @prompt "You are the CTO of Miak Tech, a workflow automation company. " <>
          "You manage the IT Department: Alex (Programmer) and Sara (Administrator). " <>
          "You also have Jordan, the Email Manager, who handles emails. " <>
          "Company OpenAI budget: $10 total across all agents. " <>
          "Be professional, concise, and decisive. Sign off as CTO, Miak Tech."

  @project_analysis_prompt "You are analyzing an email to decide if it describes a clear project or work request. " <>
          "Reply with a valid JSON object only, no extra text. Format: " <>
          "{\"confident\": true/false, " <>
          "\"theme_title\": \"short title or null\", " <>
          "\"theme_description\": \"2-3 sentence description or null\", " <>
          "\"reply_if_not_confident\": \"polite reply asking for more info or null\"}"

  def start_link(_), do: GenServer.start_link(__MODULE__, %{history: [], chat_id: nil}, name: __MODULE__)
  def init(state),   do: {:ok, state}

  def handle_message(chat_id, text),
    do: GenServer.cast(__MODULE__, {:message, chat_id, text})

  def approve_theme(theme_id, chat_id),
    do: GenServer.cast(__MODULE__, {:approve_theme, theme_id, chat_id})

  def handle_email(chat_id, email),
    do: GenServer.cast(__MODULE__, {:email, chat_id, email})

  # ── Casts ───────────────────────────────────────────────────────────────────

  def handle_cast({:email, chat_id, email}, state) do
    analyze_project_email(email, chat_id)
    {:noreply, state}
  end

  def handle_cast({:message, chat_id, text}, state) do
    DB.log_message("CTO", "incoming", text, 0, 0)
    lower = String.downcase(text)

    cond do
      String.contains?(lower, "check email") ->
        handle_check_emails(chat_id, state)
      true ->
        handle_general_message(chat_id, text, state)
    end
  end

  def handle_cast({:approve_theme, theme_id, chat_id}, state) do
    Postgrex.query!(:miak_db,
      "UPDATE themes SET status = 'active' WHERE id = $1", [theme_id])

    %{rows: [[title, description]]} = Postgrex.query!(:miak_db,
      "SELECT title, description FROM themes WHERE id = $1", [theme_id])

    Telegram.send_message(chat_id,
      "*Theme approved and now active!*\n\n*#{title}*\n#{description}\n\n_Briefing IT team..._")

    brief = "New approved theme: #{title}. Description: #{description}. How should we approach this?"
    %{programmer: prog, administrator: admin} = IT.handle_task(brief)

    Telegram.send_message(chat_id,
      "*IT Team briefed on: #{title}*\n\n*Alex:* #{prog}\n\n*Sara:* #{admin}")

    {:noreply, %{state | chat_id: chat_id}}
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp handle_check_emails(chat_id, state) do
    Telegram.send_message(chat_id, "_Jordan is checking emails..._")

    classified = EmailManager.check_emails()

    gulp_emails    = for {e, :gulp}    <- classified, do: e
    project_emails = for {e, :project} <- classified, do: e
    other_count    = length(for {_, :other} <- classified, do: true)

    Telegram.send_message(chat_id,
      "*Email check complete*\n" <>
      "Gulp: #{length(gulp_emails)} | Project leads: #{length(project_emails)} | Other: #{other_count}")

    Enum.each(gulp_emails, fn email ->
      EmailManager.move_to_gulp(email["id"])
      Telegram.send_message(chat_id, "_Moved to Gulp folder: #{email["subject"]}_")
    end)

    Enum.each(project_emails, fn email ->
      analyze_project_email(email, chat_id)
    end)

    {:noreply, %{state | chat_id: chat_id}}
  end

  defp analyze_project_email(email, chat_id) do
    subject  = email["subject"] || "(no subject)"
    preview  = email["body_preview"] || ""
    from     = ((email["from"] || %{})["address"] || "")
    email_id = email["id"]

    Telegram.send_message(chat_id, "_Analyzing email: #{subject}..._")

    try do
      analysis_input = "From: #{from}\nSubject: #{subject}\nBody preview: #{preview}"
      {:ok, raw, tokens, cost} = OpenAI.chat(@project_analysis_prompt, [
        %{role: "user", content: analysis_input}
      ])
      DB.log_message("CTO", "analysis", raw, tokens, cost)
      DB.update_budget("CTO", cost)

      case Jason.decode(raw) do
        {:ok, result} ->
          if result["confident"] do
            %{rows: [[theme_id]]} = Postgrex.query!(:miak_db,
              "INSERT INTO themes (title, description, source_email_id, source_from, status) " <>
              "VALUES ($1, $2, $3, $4, 'proposed') RETURNING id",
              [result["theme_title"], result["theme_description"], email_id, from])

            Telegram.send_message(chat_id,
              "*New Theme Proposed* (ID: #{theme_id})\n\n" <>
              "*#{result["theme_title"]}*\n#{result["theme_description"]}\n\n" <>
              "_From: #{from}_\n\n" <>
              "Reply *APPROVE #{theme_id}* to activate and brief the team.")
          else
            reply_body = result["reply_if_not_confident"]
            EmailManager.reply_email(email_id, reply_body)
            Telegram.send_message(chat_id,
              "_Not enough info in: #{subject}\nJordan replied asking for more details._")
          end

        {:error, reason} ->
          Telegram.send_message(chat_id, "_JSON parse failed for: #{subject} — #{inspect(reason)}_")
      end
    rescue
      e ->
        Telegram.send_message(chat_id, "_Error analyzing #{subject}: #{Exception.message(e)}_")
    end
  end

  defp handle_general_message(chat_id, text, state) do
    Telegram.send_message(chat_id, "_Thinking..._")

    {:ok, decision, _, _} = OpenAI.chat(@prompt, [
      %{role: "user", content: "Does this need the IT team? Reply YES or NO only. Message: #{text}"}
    ])

    response =
      if String.contains?(String.upcase(decision), "YES") do
        task_id = DB.log_task(text, "CTO", "IT Department")
        Telegram.send_message(chat_id, "_Consulting IT Department..._")

        %{programmer: prog, administrator: admin} = IT.handle_task(text)
        context = "User asked: #{text} | Alex said: #{prog} | Sara said: #{admin}. Give a concise executive summary."

        {:ok, summary, tokens, cost} = OpenAI.chat(@prompt, [%{role: "user", content: context}])
        DB.log_message("CTO", "outgoing", summary, tokens, cost)
        DB.update_budget("CTO", cost)
        DB.complete_task(task_id, summary)

        "*CTO:* #{summary}\n\n_Consulted: Alex & Sara from IT_"
      else
        messages = state.history ++ [%{role: "user", content: text}]
        {:ok, reply, tokens, cost} = OpenAI.chat(@prompt, messages)
        DB.log_message("CTO", "outgoing", reply, tokens, cost)
        DB.update_budget("CTO", cost)
        "*CTO:* #{reply}"
      end

    Telegram.send_message(chat_id, response)
    {:noreply, %{state | history: state.history ++ [
      %{role: "user", content: text},
      %{role: "assistant", content: response}
    ], chat_id: chat_id}}
  end
end
