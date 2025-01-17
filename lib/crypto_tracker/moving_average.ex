defmodule CryptoTracker.MovingAverage do
  @moduledoc """
  Calculates and maintains real-time Simple Moving Averages (SMA) for Bitcoin price data.

  This GenServer-based module is responsible for calculating the 5-minute Simple Moving
  Average of Bitcoin prices. It works by periodically fetching recent price data from
  the TimeSeriesStore, computing the average, and making it available to other system
  components.

  ## Features

  * Automatic periodic SMA calculations
  * Configurable time window and calculation frequency
  * Error handling for missing or insufficient data
  * Monitoring of significant SMA changes
  * Clean API for retrieving current SMA values

  ## Technical Details

  The module:
  * Maintains the most recent SMA value in its state
  * Updates calculations every second by default
  * Uses a 5-minute rolling window for calculations
  * Logs significant changes (>1% movement)

  ## Usage Example

      # Start the MovingAverage calculator
      CryptoTracker.MovingAverage.start_link([])

      # Get the current SMA value
      case CryptoTracker.MovingAverage.get_current_sma() do
        {:ok, sma} -> 
          # Use the SMA value
          Logger.info("Current SMA: " <> sma)
        {:error, :no_data_available} ->
          # Handle the error case
          Logger.warn("SMA not yet available")
      end

  ## Integration

  This module is designed to work with:
  * TimeSeriesStore - Source of price data
  * PriceAnalyzer - Consumer of SMA calculations

  The module automatically fetches data from TimeSeriesStore and makes calculations
  available to PriceAnalyzer through its public API.
  """

  use GenServer
  require Logger

  # 5 minutes in seconds
  @sma_window 300
  # 1 second in milliseconds
  @calculation_interval 1_000

  @doc """
  Starts the MovingAverage calculator GenServer.

  This function initializes the GenServer with empty state and begins the periodic
  calculation cycle. It should be started under the application's supervision tree.

  ## Parameters

  * `_` - Ignores any arguments as none are needed for initialization

  ## Returns

  * `{:ok, pid}` if the process starts successfully
  * `{:error, reason}` if the process fails to start

  ## Example

      {:ok, pid} = CryptoTracker.MovingAverage.start_link([])
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Retrieves the current Simple Moving Average value.

  This function provides a synchronous way to get the most recently calculated
  SMA value. It will return an error if no SMA has been calculated yet.

  ## Returns

  * `{:ok, float()}` - The current SMA value if available
  * `{:error, :no_data_available}` - If no SMA has been calculated yet

  ## Example

      case CryptoTracker.MovingAverage.get_current_sma() do
        {:ok, sma} -> "Current SMA: " <> sma
        {:error, _} -> "No SMA available yet"
      end
  """
  def get_current_sma do
    GenServer.call(__MODULE__, :get_sma)
  end

  @doc false
  def init(_) do
    schedule_calculation()
    {:ok, %{current_sma: nil, last_calculation_time: nil}}
  end

  @doc false
  def handle_call(:get_sma, _from, state) do
    {:reply, format_sma_response(state), state}
  end

  @doc false
  def handle_info(:calculate, state) do
    new_state = calculate_new_sma(state)
    schedule_calculation()
    {:noreply, new_state}
  end

  defp calculate_new_sma(state) do
    case CryptoTracker.TimeSeriesStore.get_last_n_minutes(@sma_window) do
      [] ->
        Logger.warning("No price data available for SMA calculation")
        state

      price_data ->
        sma = calculate_average(price_data)
        now = System.system_time(:second)
        log_significant_changes(state.current_sma, sma)
        %{state | current_sma: sma, last_calculation_time: now}
    end
  end

  defp calculate_average(price_data) do
    {sum, count} =
      price_data
      |> Enum.reduce({0, 0}, fn {_timestamp, data}, {sum, count} ->
        {sum + data.price, count + 1}
      end)

    case count do
      0 -> 0.0
      _ -> sum / count
    end
  end

  defp format_sma_response(%{current_sma: nil}), do: {:error, :no_data_available}
  defp format_sma_response(%{current_sma: sma}), do: {:ok, sma}

  defp schedule_calculation do
    Process.send_after(self(), :calculate, @calculation_interval)
  end

  defp log_significant_changes(nil, _new_sma), do: :ok

  defp log_significant_changes(old_sma, new_sma) do
    percent_change = abs((new_sma - old_sma) / old_sma * 100)

    if percent_change > 1.0 do
      Logger.info(
        "Significant SMA change detected: #{Float.round(percent_change, 2)}% " <>
          "(#{Float.round(old_sma, 2)} -> #{Float.round(new_sma, 2)})"
      )
    end
  end
end

