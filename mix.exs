defmodule CommandRunner.MixProject do
  use Mix.Project

  def project do
    [
      app: :command_runner,
      version: "0.2.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.travis": :test
      ],
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],
      description: description(),
      package: package(),

      # Docs
      name: "CommandRunner",
      source_url: "http://github.com/tlux/command_runner",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.3", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:excoveralls, "~> 0.12", only: :test},
      {:liveness, "~> 1.0", only: :test}
    ]
  end

  defp description do
    "An Elixir library providing a simple API to start and stop shell commands."
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/tlux/command_runner"
      }
    ]
  end
end
