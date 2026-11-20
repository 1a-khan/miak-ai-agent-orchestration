defmodule MiakTech.MixProject do
  use Mix.Project

  def project do
    [
      app: :miak_tech,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MiakTech.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.19"},
      {:decimal, "~> 2.1"}
    ]
  end
end
