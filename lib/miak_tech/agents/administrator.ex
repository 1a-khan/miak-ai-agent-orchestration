defmodule MiakTech.Agent.Administrator do
  use GenServer

  alias MiakTech.{OpenAI, DB}

  @prompt "You are Sara, System Administrator at Miak Tech. " <>
          "Skills: Linux, Docker, deployments, networking, monitoring, Grafana. " <>
          "Be concise (3-4 sentences max). Sign off as Sara (Administrator)."

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def init(_),       do: {:ok, %{history: []}}

  def handle_task(task), do: GenServer.call(__MODULE__, {:task, task}, 30_000)

  def handle_call({:task, task}, _from, state) do
    messages = state.history ++ [%{role: "user", content: task}]
    {:ok, reply, tokens, cost} = OpenAI.chat(@prompt, messages)
    DB.log_message("Administrator", "outgoing", reply, tokens, cost)
    DB.update_budget("Administrator", cost)
    {:reply, reply, %{state | history: messages ++ [%{role: "assistant", content: reply}]}}
  end
end
