defmodule Matterlix.MixProject do
  use Mix.Project

  @app :matterlix
  @version "0.3.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: make_env(),
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/tomHoenderdos/matterlix",
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"],
      source_url: "https://github.com/tomHoenderdos/matterlix",
      source_ref: "v#{@version}",
      groups_for_modules: [
        "High-Level API": [Matterlix.Matter],
        "Low-Level NIF": [Matterlix.Matter.NIF]
      ]
    ]
  end

  defp description do
    "Elixir NIF bindings for the Matter (CHIP) SDK, designed for Nerves-based IoT devices"
  end

  defp package do
    [
      name: "matterlix",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/tomHoenderdos/matterlix"
      },
      files: ~w(
        lib c_src Makefile matter_sdk_includes.mk
        mix.exs README.md CHANGELOG.md LICENSE
      )
    ]
  end

  defp make_env do
    profile = Application.get_env(:matterlix, :device_profile, :light)
    env = %{"MATTER_PROFILE" => to_string(profile)}

    if Application.get_env(:matterlix, :debug, false) do
      Map.put(env, "MATTER_DEBUG", "1")
    else
      env
    end
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Matterlix.Application, []}
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
