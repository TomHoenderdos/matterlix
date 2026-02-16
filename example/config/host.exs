import Config

# Host-specific configuration for development without hardware

# Logger configuration for development
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Handler for attribute change events (same module as target)
config :matterlix, handler: Example.MatterLight

# Note: On host, Circuits.GPIO will not be available.
# The application handles this gracefully and runs in simulation mode.
# You can use the simulation functions to test:
#
#   Example.PairingButton.simulate_short_press()
#   Example.PairingButton.simulate_long_press()
#   Example.StatusLed.set_mode(:pairing)
