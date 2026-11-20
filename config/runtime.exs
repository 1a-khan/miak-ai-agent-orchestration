import Config

# All secrets come from environment variables — never hardcoded.
# For local dev: copy .env.example to .env and source it before running.
# For production (Coolify): set these as environment variables in the app config.

config :miak_tech,
  openai_api_key: System.fetch_env!("OPENAI_API_KEY"),
  telegram_token: System.fetch_env!("TELEGRAM_TOKEN"),
  windmill_token: System.fetch_env!("WINDMILL_TOKEN")

config :miak_tech, MiakTech.Grafana,
  loki_url: System.fetch_env!("GRAFANA_LOKI_URL"),
  loki_user: System.fetch_env!("GRAFANA_LOKI_USER"),
  api_key: System.fetch_env!("GRAFANA_API_KEY")

config :miak_tech, MiakTech.DB,
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  database: System.get_env("DB_NAME", "oban_elixir"),
  username: System.get_env("DB_USER", "oban"),
  password: System.fetch_env!("DB_PASSWORD")
