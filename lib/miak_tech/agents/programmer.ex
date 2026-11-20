defmodule MiakTech.Agent.Programmer do
  use GenServer

  alias MiakTech.{OpenAI, DB}

  @prompt "You are Alex, Senior Programmer at Miak Tech. " <>
            "Skills: Elixir, Python, REST APIs, automation, databases. " <>
            "Be concise (3-4 sentences max). Sign off as Alex (Programmer)."

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def init(_), do: {:ok, %{history: []}}

  def handle_task(task), do: GenServer.call(__MODULE__, {:task, task}, 30_000)

  def handle_call({:task, task}, _from, state) do
    messages = state.history ++ [%{role: "user", content: task}]
    {:ok, reply, tokens, cost} = OpenAI.chat(@prompt, messages)
    DB.log_message("Programmer", "outgoing", reply, tokens, cost)
    DB.update_budget("Programmer", cost)
    {:reply, reply, %{state | history: messages ++ [%{role: "assistant", content: reply}]}}
  end
end
