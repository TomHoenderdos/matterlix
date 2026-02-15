defmodule Mix.Tasks.Matterlix.BuildSdk do
  @shortdoc "Build Matter SDK for a device profile"
  @moduledoc """
  Builds the Matter SDK inside a Docker container for the specified device profile.

  ## Usage

      mix matterlix.build_sdk                    # Uses configured or default (:light) profile
      mix matterlix.build_sdk --profile lock      # Build for a specific profile
      mix matterlix.build_sdk --list              # List available profiles

  ## Configuration

  The default profile can be set in your config:

      config :matterlix, device_profile: :light

  ## Requirements

  - Docker must be installed and running
  - The Matter SDK must be checked out at `deps/connectedhomeip`
  - Apple Silicon Mac recommended (native arm64 Docker build)

  ## What it does

  1. Builds the Matter SDK example app for the selected profile in Docker
  2. Generates `matter_sdk_includes.mk` from the build output
  3. Writes a `.matter_profile` marker file for the current profile

  After building, compile as normal with `MIX_TARGET=<target> mix firmware`.
  """

  use Mix.Task

  @profiles_module Matterlix.DeviceProfiles
  @docker_image "matterlix-arm64-builder"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [profile: :string, list: :boolean],
        aliases: [p: :profile, l: :list]
      )

    if opts[:list] do
      list_profiles()
    else
      profile_name = resolve_profile(opts[:profile])
      build_sdk(profile_name)
    end
  end

  defp list_profiles do
    Mix.shell().info("Available Matter device profiles:\n")

    @profiles_module.list()
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.each(fn {name, profile} ->
      Mix.shell().info("  #{name}")
      Mix.shell().info("    #{profile.description}")
      Mix.shell().info("    GN root: #{profile.gn_root}")
      Mix.shell().info("")
    end)
  end

  defp resolve_profile(nil) do
    Application.get_env(:matterlix, :device_profile, :light)
  end

  defp resolve_profile(name) when is_binary(name) do
    atom = String.to_atom(name)

    unless @profiles_module.valid?(atom) do
      Mix.raise(
        "Unknown device profile: #{name}. Run `mix matterlix.build_sdk --list` to see available profiles."
      )
    end

    atom
  end

  defp build_sdk(profile_name) do
    profile = @profiles_module.get!(profile_name)
    sdk_path = Path.expand("deps/connectedhomeip")
    project_root = File.cwd!()

    unless File.dir?(sdk_path) do
      Mix.raise("Matter SDK not found at #{sdk_path}. Run `mix deps.get` first.")
    end

    Mix.shell().info("Building Matter SDK for profile: #{profile_name}")
    Mix.shell().info("  GN root: #{profile.gn_root}")
    Mix.shell().info("  Executable: #{profile.executable}")

    # Step 1: Ensure Docker image is built
    ensure_docker_image(project_root)

    # Step 2: Run Docker build with profile env vars
    run_docker_build(sdk_path, project_root, profile_name, profile)

    # Step 3: Generate matter_sdk_includes.mk
    build_dir = Path.join(sdk_path, "out/linux-arm64-#{profile_name}")
    generate_includes(project_root, build_dir, profile_name)

    # Step 4: Write profile marker
    File.write!(Path.join(project_root, ".matter_profile"), to_string(profile_name))

    Mix.shell().info("\nBuild complete! Profile '#{profile_name}' is ready.")
    Mix.shell().info("Compile with: MIX_TARGET=<target> mix compile")
  end

  defp ensure_docker_image(project_root) do
    Mix.shell().info("\nChecking Docker image...")
    docker_dir = Path.join(project_root, "docker")

    {output, status} =
      System.cmd("docker", ["images", "-q", @docker_image], stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("Docker is not available. Please install and start Docker.")
    end

    if String.trim(output) == "" do
      Mix.shell().info("Building Docker image (first time only)...")

      {_, status} =
        System.cmd(
          "docker",
          [
            "build",
            "--platform",
            "linux/arm64",
            "-t",
            @docker_image,
            "-f",
            Path.join(docker_dir, "Dockerfile.arm64"),
            docker_dir
          ],
          into: IO.stream(:stdio, :line)
        )

      if status != 0, do: Mix.raise("Failed to build Docker image")
    else
      Mix.shell().info("Docker image found.")
    end
  end

  defp run_docker_build(sdk_path, _project_root, profile_name, profile) do
    Mix.shell().info("\nStarting Matter SDK build in Docker...")
    Mix.shell().info("This may take 20-30 minutes for the first build.\n")

    docker_args = [
      "run",
      "--rm",
      "--platform",
      "linux/arm64",
      "-v",
      "#{sdk_path}:/matter/connectedhomeip",
      "-e",
      "MATTER_GN_ROOT=#{profile.gn_root}",
      "-e",
      "MATTER_OUTPUT_NAME=#{profile_name}",
      "-e",
      "MATTER_EXECUTABLE=#{profile.executable}",
      @docker_image
    ]

    {_, status} = System.cmd("docker", docker_args, into: IO.stream(:stdio, :line))

    if status != 0 do
      Mix.raise("Docker build failed for profile '#{profile_name}'")
    end
  end

  defp generate_includes(project_root, build_dir, profile_name) do
    Mix.shell().info("\nGenerating matter_sdk_includes.mk...")
    script = Path.join(project_root, "scripts/gen_matter_includes.sh")
    output_file = Path.join(project_root, "matter_sdk_includes.mk")

    {_, status} =
      System.cmd("bash", [script, build_dir, to_string(profile_name), output_file],
        into: IO.stream(:stdio, :line)
      )

    if status != 0 do
      Mix.raise("Failed to generate matter_sdk_includes.mk")
    end
  end
end
