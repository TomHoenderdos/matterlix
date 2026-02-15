defmodule Matterlix.DeviceProfiles do
  @moduledoc """
  Pre-defined Matter device profiles.

  Each profile maps to a Matter SDK example app with a specific set of clusters.
  The profile determines the ZAP file used for code generation and which cluster
  implementations are compiled into the Matter SDK build.

  ## Configuration

      config :matterlix, device_profile: :light

  ## Available Profiles

  | Profile | Clusters | Use Case |
  |---------|----------|----------|
  | `:light` | OnOff, LevelControl, ColorControl | Dimmable color light |
  | `:contact_sensor` | BooleanState | Door/window sensor |
  | `:lock` | DoorLock | Smart lock |
  | `:thermostat` | Thermostat | HVAC control |
  | `:air_quality_sensor` | AirQuality, Temperature, Humidity | Environmental sensing |
  | `:all_clusters` | All standard clusters | Development/testing |

  ## Building for a Profile

      mix matterlix.build_sdk --profile light
  """

  @type profile :: %{
          gn_root: String.t(),
          executable: String.t(),
          description: String.t()
        }

  @profiles %{
    light: %{
      gn_root: "examples/lighting-app/linux",
      executable: "chip-lighting-app",
      description: "Dimmable light (OnOff + LevelControl + ColorControl)"
    },
    contact_sensor: %{
      gn_root: "examples/contact-sensor-app/linux",
      executable: "contact-sensor-app",
      description: "Contact sensor (BooleanState)"
    },
    lock: %{
      gn_root: "examples/lock-app/linux",
      executable: "chip-lock-app",
      description: "Door lock (DoorLock cluster)"
    },
    thermostat: %{
      gn_root: "examples/thermostat/linux",
      executable: "thermostat-app",
      description: "Thermostat"
    },
    air_quality_sensor: %{
      gn_root: "examples/air-quality-sensor-app/linux",
      executable: "air-quality-sensor-app",
      description: "Air quality + temperature + humidity"
    },
    all_clusters: %{
      gn_root: "examples/all-clusters-app/linux",
      executable: "chip-all-clusters-app",
      description: "All clusters (development/testing)"
    }
  }

  @doc "Get a device profile by name. Raises if not found."
  @spec get!(atom()) :: profile()
  def get!(name) do
    case Map.fetch(@profiles, name) do
      {:ok, profile} ->
        profile

      :error ->
        raise ArgumentError,
              "Unknown device profile: #{inspect(name)}. Available: #{inspect(Map.keys(@profiles))}"
    end
  end

  @doc "Get a device profile by name."
  @spec get(atom()) :: {:ok, profile()} | :error
  def get(name), do: Map.fetch(@profiles, name)

  @doc "List all available profiles."
  @spec list() :: %{atom() => profile()}
  def list, do: @profiles

  @doc "Check if a profile name is valid."
  @spec valid?(atom()) :: boolean()
  def valid?(name), do: Map.has_key?(@profiles, name)
end
