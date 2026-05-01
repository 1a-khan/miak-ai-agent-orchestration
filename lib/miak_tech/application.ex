defmodule MiakTech.Application do
  use Application

  alias MiakTech.{DB, TelegramPoller}
  alias MiakTech.{Department.IT, Agent.EmailManager, Agent.Aria, Agent.CTO}

  @impl true
  def start(_type, _args) do
    children = [
      DB,
      IT,
      EmailManager,
      Aria,
      CTO,
      TelegramPoller,
      MiakTech.MetricsPusher
    ]

    opts   = [strategy: :one_for_one, name: MiakTech.Supervisor, max_restarts: 20, max_seconds: 60]
    result = Supervisor.start_link(children, opts)

    # DB migrations + seed run after Postgrex is up
    DB.setup()
    DB.seed_agents()

    result
  end
end
