defmodule MiakTech.Telegram do
  def token, do: Application.fetch_env!(:miak_tech, :telegram_token)
  def base,  do: "https://api.telegram.org/bot#{token()}"

  def send_message(chat_id, text) do
    Req.post!("#{base()}/sendMessage",
      json: %{chat_id: chat_id, text: text, parse_mode: "Markdown"})
  end

  def get_updates(offset) do
    Req.get!("#{base()}/getUpdates",
      params: [offset: offset, timeout: 10]).body["result"] || []
  end

  def get_file(file_id) do
    token = token()
    base  = base()

    resp      = Req.get!("#{base}/getFile", params: [file_id: file_id])
    file_path = resp.body["result"]["file_path"]
    filename  = Path.basename(file_path)

    file_resp = Req.get!("https://api.telegram.org/file/bot#{token}/#{file_path}")

    if file_resp.status == 200 do
      {:ok, file_resp.body, filename}
    else
      {:error, "HTTP #{file_resp.status}"}
    end
  end
end
