import Config

# Target-specific configuration for Raspberry Pi and other Nerves devices

# Use shoehorn to start the main application
config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Use RingLogger for on-device logging
config :logger, backends: [RingLogger]

# Nerves Runtime configuration
config :nerves_runtime, :kernel, use_system_registry: false

# VintageNet networking configuration
config :vintage_net,
  regulatory_domain: "US",
  config: [
    # WiFi interface - configured dynamically during Matter commissioning
    {"wlan0", %{type: VintageNetWiFi}},
    # Ethernet fallback with DHCP
    {"eth0", %{type: VintageNetEthernet, ipv4: %{method: :dhcp}}}
  ]

# mDNS for device discovery
config :mdns_lite,
  hosts: [:hostname, "matterlix"],
  ttl: 120,
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    }
  ]

# SSH access for debugging
keys =
  [
    Path.join([System.user_home!(), ".ssh", "id_rsa.pub"]),
    Path.join([System.user_home!(), ".ssh", "id_ed25519.pub"])
  ]
  |> Enum.filter(&File.exists?/1)

if keys != [] do
  config :nerves_ssh,
    authorized_keys: Enum.map(keys, &File.read!/1)
end

# GPIO pin configuration for Raspberry Pi
# Using BCM numbering (not physical pin numbers)
#
# Physical layout reference:
#   Pin 11 = GPIO 17 (LED)
#   Pin 13 = GPIO 27 (Button)
#   Pin 14 = GND (for button and LED)
#
config :example,
  status_led_pin: 17,
  pairing_button_pin: 27

# Matter commissioning configuration
# Set fixed values so you can prepare the pairing code before flashing
#
# With these default test values, your manual pairing code will be: 34970112332
# You can also generate a QR code from: MT:Y.K9042C00KA0648G00
#
# To commission with chip-tool:
#   chip-tool pairing code 1 34970112332
#
config :matterlix,
  # Setup PIN code (8 digits, 1-99999998)
  # 20202021 is the Matter SDK default test PIN
  setup_pin: 20202021,
  # Discriminator (12-bit, 0-4095)
  # 3840 (0xF00) is a common test value
  discriminator: 3840
