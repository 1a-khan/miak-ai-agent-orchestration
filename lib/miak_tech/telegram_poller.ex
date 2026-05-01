defmodule MiakTech.TelegramPoller do
  use GenServer

  alias MiakTech.{Telegram, DB}
  alias MiakTech.Agent.{CTO, EmailManager, Aria, Programmer, Administrator}

  def start_link(_), do: GenServer.start_link(__MODULE__, %{offset: 0}, name: __MODULE__)

  def init(state) do
    schedule()
    {:ok, state}
  end

  def handle_info(:poll, state) do
    updates = try do
      Telegram.get_updates(state.offset)
    rescue
      e ->
        schedule(5_000)
        {:error, e}
    end

    if match?({:error, _}, updates) do
      {:noreply, state}
    else

    new_offset = Enum.reduce(updates, state.offset, fn update, _acc ->
      if msg = update["message"] do
        chat_id = msg["chat"]["id"]
        text    = msg["text"] || ""
        photo   = msg["photo"]
        caption = msg["caption"] || ""

        cond do
          photo != nil ->
            file_id = photo |> List.last() |> Map.get("file_id")
            Aria.handle_photo(chat_id, file_id, caption)

          Regex.match?(~r/^APPROVE\s+(\d+)$/i, text) ->
            [_, id] = Regex.run(~r/^APPROVE\s+(\d+)$/i, text)
            CTO.approve_theme(String.to_integer(id), chat_id)

          Regex.match?(~r/^budget$/i, text) ->
            rows   = DB.budget_report()
            report = Enum.map_join(rows, "\n", fn [name, total, used] ->
              total_f   = Decimal.to_float(total)
              used_f    = Decimal.to_float(used)
              remaining = Float.round(total_f - used_f, 4)
              pct       = if total_f > 0, do: Float.round(used_f / total_f * 100, 1), else: 0.0
              filled    = trunc(pct / 10)
              bar       = String.duplicate("█", filled) <> String.duplicate("░", 10 - filled)
              if name == "TOTAL" do
                "\n────────────────\n*TOTAL*\n  #{bar} #{pct}%\n  used $#{Float.round(used_f,4)} / $#{Float.round(total_f,2)} — *$#{remaining} left*"
              else
                "*#{name}*\n  #{bar} #{pct}%\n  used $#{Float.round(used_f,4)} / $#{Float.round(total_f,2)} — *$#{remaining} left*"
              end
            end)
            Telegram.send_message(chat_id, "*Budget Report*\n\n#{report}")

          Regex.match?(~r/^@?jordan\b/i, text) ->
            EmailManager.handle_message(chat_id, text)

          Regex.match?(~r/^@?aria\b/i, text) ->
            Aria.handle_message(chat_id, text)

          Regex.match?(~r/^@?alex\b/i, text) ->
            reply = Programmer.handle_task(text)
            Telegram.send_message(chat_id, "*Alex:* #{reply}")

          Regex.match?(~r/^@?sara\b/i, text) ->
            reply = Administrator.handle_task(text)
            Telegram.send_message(chat_id, "*Sara:* #{reply}")

          Regex.match?(~r/^@?cto\b/i, text) ->
            CTO.handle_message(chat_id, text)

          Process.whereis(Aria) != nil &&
          GenServer.call(Aria, {:has_session, chat_id}, 5_000) ->
            Aria.handle_message(chat_id, text)

          text != "" ->
            CTO.handle_message(chat_id, text)

          true ->
            :ok
        end
      end

      update["update_id"] + 1
    end)

    schedule()
    {:noreply, %{state | offset: new_offset}}
    end
  end

  defp schedule(delay \\ 1_000), do: Process.send_after(self(), :poll, delay)
end
