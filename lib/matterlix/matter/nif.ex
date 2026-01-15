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
  @spec nif_set_attribute(reference(), non_neg_integer(), non_neg_integer(), non_neg_integer(), term()) ::
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
end
