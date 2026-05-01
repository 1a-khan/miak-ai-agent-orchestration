defmodule MiakTech.OpenAI do
  @model "gpt-4o-mini"

  def chat(system_prompt, messages, retries \\ 2) do
    api_key = Application.fetch_env!(:miak_tech, :openai_api_key)

    response = Req.post!(
      "https://api.openai.com/v1/chat/completions",
      json: %{
        model: @model,
        messages: [%{role: "system", content: system_prompt} | messages],
        temperature: 0.7
      },
      headers: [{"Authorization", "Bearer #{api_key}"}],
      receive_timeout: 60_000
    )

    content = response.body["choices"] |> List.first() |> get_in(["message", "content"])
    usage   = response.body["usage"]
    input   = usage["prompt_tokens"]
    output  = usage["completion_tokens"]
    cost    = (input * 0.000150 / 1000) + (output * 0.000600 / 1000)
    {:ok, content, input + output, cost}
  rescue
    e ->
      if retries > 0 do
        Process.sleep(2_000)
        chat(system_prompt, messages, retries - 1)
      else
        reraise e, __STACKTRACE__
      end
  end

  def vision(prompt, image_b64, extra_caption \\ "") do
    api_key = Application.fetch_env!(:miak_tech, :openai_api_key)
    extra   = if extra_caption != "", do: "\nUser caption: #{extra_caption}", else: ""

    messages = [%{
      role: "user",
      content: [
        %{type: "text", text: prompt <> extra},
        %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{image_b64}"}}
      ]
    }]

    response = Req.post!(
      "https://api.openai.com/v1/chat/completions",
      json: %{model: "gpt-4o", messages: messages, max_tokens: 300},
      headers: [{"Authorization", "Bearer #{api_key}"}],
      receive_timeout: 30_000
    )

    raw = response.body["choices"] |> List.first() |> get_in(["message", "content"])

    case Jason.decode(raw) do
      {:ok, result} -> result
      {:error, _}   -> %{"category" => "other", "detected_theme" => "", "detected_project" => "", "detected_client" => "", "description" => "file"}
    end
  rescue
    _ -> %{"category" => "other", "detected_theme" => "", "detected_project" => "", "detected_client" => "", "description" => "file"}
  end
end
