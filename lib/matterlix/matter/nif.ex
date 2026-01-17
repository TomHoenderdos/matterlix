defmodule Matterlix.Matter.NIF do
  @moduledoc """
  Low-level NIF bindings for the Matter SDK.

  This module provides direct access to the C++ NIF functions.
  For a higher-level API, use `Matterlix.Matter` instead.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    nif_path = :filename.join(:code.priv_dir(:matterlix), ~c"matter_nif")

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        :ok

      {:error, {:reload, _}} ->
        :ok

      {:error, reason} ->
        IO.warn("Failed to load Matter NIF: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Initialize the Matter SDK.

  Returns `{:ok, context}` on success, or `{:error, reason}` on failure.
  The context is an opaque reference that must be passed to other NIF functions.
  """
  @spec nif_init() :: {:ok, reference()} | {:error, atom()}
  def nif_init do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Start the Matter server.

  This makes the device discoverable and commissionable on the network.
  """
  @spec nif_start_server(reference()) :: :ok | {:error, atom()}
  def nif_start_server(_context) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Stop the Matter server.
  """
  @spec nif_stop_server(reference()) :: :ok | {:error, atom()}
  def nif_stop_server(_context) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get information about the Matter device state.

  Returns a map containing device information such as:
  - `:initialized` - whether the SDK has been initialized
  - `:nif_version` - version of the NIF
  """
  @spec nif_get_info(reference()) :: {:ok, map()} | {:error, atom()}
  def nif_get_info(_context) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Set a Matter attribute value.

  ## Parameters
  - `context` - The Matter context
  - `endpoint_id` - The endpoint ID (usually 1 for simple devices)
  - `cluster_id` - The cluster ID (e.g., 0x0006 for On/Off)
  - `attribute_id` - The attribute ID within the cluster
  - `value` - The value to set
  """
  @spec nif_set_attribute(
          reference(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          term()
        ) ::
          :ok | {:error, atom()}
  def nif_set_attribute(_context, _endpoint_id, _cluster_id, _attribute_id, _value) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get a Matter attribute value.

  ## Parameters
  - `context` - The Matter context
  - `endpoint_id` - The endpoint ID
  - `cluster_id` - The cluster ID
  - `attribute_id` - The attribute ID
  """
  @spec nif_get_attribute(reference(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, term()} | {:error, atom()}
  def nif_get_attribute(_context, _endpoint_id, _cluster_id, _attribute_id) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Open the commissioning window to allow pairing.
  """
  @spec nif_open_commissioning_window(reference(), integer()) :: :ok | {:error, atom()}
  def nif_open_commissioning_window(_context, _timeout_seconds) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get the setup payload (QR code string and manual pairing code).
  """
  @spec nif_get_setup_payload(reference()) :: {:ok, map()} | {:error, atom()}
  def nif_get_setup_payload(_context) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Register the calling process to receive Matter events.
  """
  @spec nif_register_callback(reference()) :: :ok | {:error, atom()}
  def nif_register_callback(_context) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Schedule a factory reset of the device.
  """
  @spec nif_factory_reset(reference()) :: :ok | {:error, atom()}
  def nif_factory_reset(_context) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Set device metadata (Vendor ID, Product ID, etc.).
  Must be called before starting the server.
  """
  @spec nif_set_device_info(reference(), integer(), integer(), integer(), binary()) ::
          :ok | {:error, atom()}
  def nif_set_device_info(_context, _vid, _pid, _software_ver, _serial_number) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Report the result of a WiFi connection attempt (Network Commissioning).
  Called by Elixir in response to a {:connect_network, ...} message.
  """
  @spec nif_wifi_connect_result(reference(), integer()) :: :ok | {:error, atom()}
  def nif_wifi_connect_result(_context, _status) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Set the commissioning info (setup PIN and discriminator).
  Must be called before starting the server for values to take effect.

  ## Parameters
  - `context` - The Matter context
  - `setup_pin` - Setup PIN code (1-99999998, some values invalid)
  - `discriminator` - 12-bit discriminator (0-4095)

  ## Example

      :ok = nif_set_commissioning_info(ctx, 20202021, 3840)
  """
  @spec nif_set_commissioning_info(reference(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, atom()}
  def nif_set_commissioning_info(_context, _setup_pin, _discriminator) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
