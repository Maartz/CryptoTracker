defmodule CryptoTracker.PriceFetcher do
  @moduledoc """
  A module responsible for fetching real-time Bitcoin price data from Binance WebSocket API
  and storing it in an ETS database.

  Uses WebSockex to maintain a stable WebSocket connection with Binance and implements
  throttling logic to ensure consistent data storage frequency.

  ## How it Works

  The module maintains a persistent WebSocket connection with Binance and receives 
  real-time price updates. For each update, it:
    - Parses incoming JSON data
    - Extracts relevant information (price, high, low, volume)
    - Stores this data in an ETS table via TimeSeriesStore
    
  To prevent database overload, the module implements a throttling mechanism that ensures
  new entries are only saved once per second, even if Binance sends more frequent updates.

  ## Data Structure

  Each entry saved in ETS contains:
    - timestamp: (integer) Unix timestamp in seconds
    - price_data: (map) %{
        price: (float) Current price
        high_24h: (float) 24-hour high
        low_24h: (float) 24-hour low
        volume_24h: (float) 24-hour volume
      }

  ## Usage Example

  To start the PriceFetcher:

      iex> CryptoTracker.PriceFetcher.start_link([])
      {:ok, pid}

  Data will be automatically saved to ETS and can be queried via:

      iex> CryptoTracker.TimeSeriesStore.get_last_n_minutes(5)
      [{timestamp, price_data}, ...]

  ## Configuration

  The module uses several configured constants:
    - @save_interval_ms: Minimum interval between saves (1000ms)
    - WebSocket endpoint: "wss://stream.binance.com:9443/ws/btcusdt@ticker"
  """

  use WebSockex
  require Logger

  @save_interval_ms 1_000

  @doc """
  Starts the WebSocket connection to Binance.

  Initializes the connection with an initial state tracking the last save timestamp
  to implement throttling.

  Returns `{:ok, pid}` on successful connection.
  """
  def start_link(_) do
    initial_state = %{last_save: System.system_time(:millisecond)}

    WebSockex.start_link(
      "wss://stream.binance.com:9443/ws/btcusdt@ticker",
      __MODULE__,
      initial_state,
      name: __MODULE__
    )
  end

  @doc """
  Handles incoming WebSocket frames containing price data.

  Parses the JSON data, extracts price information, and saves it to ETS if enough
  time has elapsed since the last save (controlled by @save_interval_ms).

  Returns `{:ok, new_state}` where new_state contains the updated last_save timestamp.
  """
  def handle_frame({:text, msg}, state) do
    current_time = System.system_time(:millisecond)

    case Jason.decode(msg) do
      {:ok, data} ->
        price_data = %{
          price: parse_float(data["c"]),
          high_24h: parse_float(data["h"]),
          low_24h: parse_float(data["l"]),
          volume_24h: parse_float(data["v"])
        }

        if current_time - state.last_save >= @save_interval_ms do
          timestamp = System.system_time(:second)
          CryptoTracker.TimeSeriesStore.insert_price(timestamp, price_data)

          Logger.debug("Saved price data: #{inspect(price_data)}")
          {:ok, %{state | last_save: current_time}}
        else
          {:ok, state}
        end

      {:error, error} ->
        Logger.error("Failed to parse: #{inspect(error)}")
        {:ok, state}
    end
  end

  defp parse_float(str) when is_binary(str) do
    {float, _} = Float.parse(str)
    float
  end

  defp parse_float(_), do: 0.0
end

