# This file is responsible for configuring your application and its
# dependencies. This configuration is loaded before any dependency and
# is restricted to this project.

import Config

# Enable the Nerves integration with Mix
Application.start(:nerves_bootstrap)

# Default GPIO pin configuration (BCM numbering)
config :example,
  status_led_pin: 17,
  pairing_button_pin: 27

config :logger, level: :info

# Customize non-Elixir parts of the firmware
config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Set the SOURCE_DATE_EPOCH date for reproducible builds
config :nerves, source_date_epoch: "1640995200"

# Import target-specific config
if Mix.target() == :host do
  import_config "host.exs"
else
  import_config "target.exs"
end
