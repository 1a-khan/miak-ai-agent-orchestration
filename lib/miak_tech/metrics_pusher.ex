defmodule MiakTech.MetricsPusher do
  use GenServer

  @interval_ms 60_000

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_) do
    schedule()
    {:ok, []}
  end

  def handle_info(:push, state) do
    rows = MiakTech.DB.budget_report()
    MiakTech.Grafana.push_budget_metrics(rows)
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :push, @interval_ms)
end
