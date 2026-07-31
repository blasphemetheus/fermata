defmodule Fermata.MixProject do
  use Mix.Project

  def project do
    [
      app: :fermata,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:saxy, "~> 1.6"},
      {:edifice, path: "../edifice"},
      {:nx, "~> 0.13"},
      {:axon, "~> 0.8"},
      {:polaris, "~> 0.1"},
      {:exla, "~> 0.13"},
      {:stream_data, "~> 1.1", only: [:test, :dev]}
    ]
  end
end
