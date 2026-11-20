defmodule MiakTech.Grafana do
  @moduledoc """
  Pushes logs and metrics to Grafana Loki.
  All pushes are fire-and-forget (Task.start) so they never block agents.

  Metrics are pushed as structured JSON log lines with type="metric".
  Use LogQL `unwrap` to extract numeric values in Grafana dashboards.
  """

  # ── Agent activity log ───────────────────────────────────────────────────────

  def push_log(agent, direction, message) do
    Task.start(fn -> do_push(agent, direction, "log", message) end)
  end

  # ── Error / crash event ──────────────────────────────────────────────────────

  def push_error(component, reason) do
    Task.start(fn ->
      message =
        Jason.encode!(%{
          type: "error",
          component: component,
          reason: reason
        })

      do_push(component, "error", "error", message)
    end)
  end

  # ── Budget metric snapshot ────────────────────────────────────────────────────

  def push_budget_metrics(rows) do
    Task.start(fn ->
      Enum.each(rows, fn [name, total, used] ->
        if name != "TOTAL" do
          total_f = Decimal.to_float(total)
          used_f = Decimal.to_float(used)
          remaining = Float.round(total_f - used_f, 6)
          pct = if total_f > 0, do: Float.round(used_f / total_f * 100, 2), else: 0.0

          message =
            Jason.encode!(%{
              type: "metric",
              agent: name,
              budget_used: used_f,
              budget_total: total_f,
              budget_remaining: remaining,
              budget_pct: pct
            })

          do_push(name, "metric", "metric", message)
        end
      end)
    end)
  end

  # ── Internal push to Loki ────────────────────────────────────────────────────

  defp do_push(agent, direction, type, message) do
    cfg = Application.fetch_env!(:miak_tech, __MODULE__)
    url = cfg[:loki_url] <> "/loki/api/v1/push"
    user = cfg[:loki_user]
    api_key = cfg[:api_key]
    timestamp = System.os_time(:nanosecond) |> Integer.to_string()

    body = %{
      streams: [
        %{
          stream: %{
            service: "miak-tech",
            agent: agent,
            direction: direction,
            type: type
          },
          values: [[timestamp, message]]
        }
      ]
    }

    Req.post(url,
      json: body,
      auth: {:basic, "#{user}:#{api_key}"},
      receive_timeout: 10_000
    )
  rescue
    _ -> :ok
  end
end
