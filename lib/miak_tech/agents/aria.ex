defmodule MiakTech.Agent.Aria do
  use GenServer

  alias MiakTech.{OpenAI, Telegram, Windmill, DB}

  @prompt "You are Aria, Files and Media Manager at Miak Tech. " <>
            "You handle all file uploads, photos, documents, and media. " <>
            "You are friendly and concise. Sign off as Aria (Files)."

  @vision_prompt "Analyze this image and reply with JSON only, no extra text. Format: " <>
                   "{\"category\": \"invoice|photo|document|contract|other\", " <>
                   "\"detected_theme\": \"theme name if visible or empty string\", " <>
                   "\"detected_project\": \"project name if visible or empty string\", " <>
                   "\"detected_client\": \"client name if visible or empty string\", " <>
                   "\"description\": \"one sentence describing what this is\"}"

  def start_link(_), do: GenServer.start_link(__MODULE__, %{sessions: %{}}, name: __MODULE__)
  def init(state), do: {:ok, state}

  def handle_photo(chat_id, file_id, caption),
    do: GenServer.cast(__MODULE__, {:photo, chat_id, file_id, caption})

  def handle_message(chat_id, text),
    do: GenServer.cast(__MODULE__, {:message, chat_id, text})

  def handle_call({:has_session, chat_id}, _from, state),
    do: {:reply, Map.has_key?(state.sessions, chat_id), state}

  # ── Photo received ──────────────────────────────────────────────────────────

  def handle_cast({:photo, chat_id, file_id, caption}, state) do
    Telegram.send_message(chat_id, "_Aria is analyzing your file..._")

    case Telegram.get_file(file_id) do
      {:ok, file_bytes, filename} ->
        file_b64 = Base.encode64(file_bytes)
        parsed = parse_caption(caption)
        analysis = OpenAI.vision(@vision_prompt, file_b64, caption || "")

        theme = parsed[:theme] || analysis["detected_theme"] || ""
        project = parsed[:project] || analysis["detected_project"] || ""
        task = parsed[:task] || ""
        category = parsed[:category] || analysis["category"] || "other"
        client = analysis["detected_client"] || "unknown"
        theme_id = find_theme_id(theme)

        session = %{
          step: :awaiting_confirm,
          file_b64: file_b64,
          filename: filename,
          theme: theme,
          theme_id: theme_id,
          project: project,
          task: task,
          category: category,
          client: client,
          description: analysis["description"] || ""
        }

        new_sessions = Map.put(state.sessions, chat_id, session)

        missing = []
        missing = if theme == "", do: missing ++ ["theme"], else: missing
        missing = if project == "", do: missing ++ ["project"], else: missing
        missing = if task == "", do: missing ++ ["task"], else: missing

        missing_note =
          if missing != [] do
            "\n_Missing: #{Enum.join(missing, ", ")} — you can correct below_"
          else
            ""
          end

        theme_display = if theme_id, do: "#{theme} (matched)", else: "#{theme} (not matched)"

        msg =
          "*Aria: File received*\n" <>
            "_#{analysis["description"]}_\n\n" <>
            "Theme:    #{if theme == "", do: "—", else: theme_display}\n" <>
            "Project:  #{if project == "", do: "—", else: project}\n" <>
            "Task:     #{if task == "", do: "—", else: task}\n" <>
            "Category: #{category}\n" <>
            "Client:   #{client}\n" <>
            missing_note <>
            "\n\n" <>
            "Reply *YES* to upload, or correct with:\n" <>
            "`theme: X / project: Y / task: Z / category: X`"

        Telegram.send_message(chat_id, msg)
        {:noreply, %{state | sessions: new_sessions}}

      {:error, reason} ->
        Telegram.send_message(chat_id, "_Could not process file: #{reason}_")
        {:noreply, state}
    end
  end

  # ── Text message ────────────────────────────────────────────────────────────

  def handle_cast({:message, chat_id, text}, state) do
    session = Map.get(state.sessions, chat_id)

    cond do
      session && session.step == :awaiting_confirm ->
        handle_confirmation(chat_id, text, session, state)

      true ->
        {:ok, reply, tokens, cost} = OpenAI.chat(@prompt, [%{role: "user", content: text}])
        DB.log_message("Aria", "outgoing", reply, tokens, cost)
        Telegram.send_message(chat_id, "*Aria:* #{reply}")
        {:noreply, state}
    end
  end

  # ── Confirmation / correction ───────────────────────────────────────────────

  defp handle_confirmation(chat_id, text, session, state) do
    trimmed = String.trim(text) |> String.upcase()

    if trimmed == "YES" do
      do_upload(chat_id, session, state)
    else
      corrections = parse_caption(text)

      updated =
        session
        |> then(fn s ->
          if corrections[:theme],
            do: %{s | theme: corrections[:theme], theme_id: find_theme_id(corrections[:theme])},
            else: s
        end)
        |> then(fn s ->
          if corrections[:project], do: %{s | project: corrections[:project]}, else: s
        end)
        |> then(fn s -> if corrections[:task], do: %{s | task: corrections[:task]}, else: s end)
        |> then(fn s ->
          if corrections[:category], do: %{s | category: corrections[:category]}, else: s
        end)

      new_sessions = Map.put(state.sessions, chat_id, updated)

      theme_display =
        if updated.theme_id,
          do: "#{updated.theme} (matched)",
          else: "#{updated.theme} (not matched)"

      msg =
        "*Updated — confirm?*\n\n" <>
          "Theme:    #{if updated.theme == "", do: "—", else: theme_display}\n" <>
          "Project:  #{if updated.project == "", do: "—", else: updated.project}\n" <>
          "Task:     #{if updated.task == "", do: "—", else: updated.task}\n" <>
          "Category: #{updated.category}\n\n" <>
          "Reply *YES* to upload or correct again."

      Telegram.send_message(chat_id, msg)
      {:noreply, %{state | sessions: new_sessions}}
    end
  end

  defp do_upload(chat_id, session, state) do
    Telegram.send_message(chat_id, "_Uploading to S3..._")

    result =
      Windmill.run("u/ammad/files/s3_tool", %{
        action: "upload",
        file_base64: session.file_b64,
        filename: session.filename,
        client_name: session.client,
        theme_title: if(session.theme != "", do: session.theme, else: "unclassified"),
        category: session.category
      })

    if result["status"] == "success" do
      Postgrex.query!(
        :miak_db,
        "INSERT INTO files (theme_id, client_name, category, filename, original_filename, " <>
          "s3_key, s3_bucket, size_bytes, project_name, task_name, uploaded_by) " <>
          "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'telegram')",
        [
          session.theme_id,
          session.client,
          session.category,
          result["filename"],
          result["original_filename"],
          result["s3_key"],
          result["s3_bucket"],
          result["size_bytes"],
          session.project,
          session.task
        ]
      )

      DB.log_message("Aria", "upload", result["s3_key"], 0, 0)

      Telegram.send_message(
        chat_id,
        "*Aria: Uploaded successfully*\n\n" <>
          "Theme:    #{if session.theme != "", do: session.theme, else: "unclassified"}\n" <>
          "Project:  #{if session.project != "", do: session.project, else: "—"}\n" <>
          "Task:     #{if session.task != "", do: session.task, else: "—"}\n" <>
          "Category: #{session.category}\n" <>
          "File:     #{result["filename"]}\n" <>
          "Size:     #{Float.round(result["size_bytes"] / 1024, 1)} KB\n\n" <>
          "[View file](#{result["presigned_url"]})"
      )

      {:noreply, %{state | sessions: Map.delete(state.sessions, chat_id)}}
    else
      Telegram.send_message(chat_id, "_Upload failed. Please try again._")
      {:noreply, state}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp parse_caption(nil), do: %{}
  defp parse_caption(""), do: %{}

  defp parse_caption(text) do
    %{}
    |> put_if_found(text, :theme, ~r/theme:\s*([^\/\n]+)/i)
    |> put_if_found(text, :project, ~r/project:\s*([^\/\n]+)/i)
    |> put_if_found(text, :task, ~r/task:\s*([^\/\n]+)/i)
    |> put_if_found(text, :category, ~r/category:\s*([^\/\n]+)/i)
  end

  defp put_if_found(map, text, key, regex) do
    case Regex.run(regex, text) do
      [_, value] ->
        cleaned = String.trim(value)
        if cleaned != "", do: Map.put(map, key, cleaned), else: map

      _ ->
        map
    end
  end

  defp find_theme_id(""), do: nil
  defp find_theme_id(nil), do: nil

  defp find_theme_id(theme_name) do
    %{rows: rows} =
      Postgrex.query!(
        :miak_db,
        "SELECT id FROM themes WHERE LOWER(title) LIKE LOWER($1) AND status = 'active' LIMIT 1",
        ["%#{theme_name}%"]
      )

    case rows do
      [[id]] -> id
      _ -> nil
    end
  end
end
