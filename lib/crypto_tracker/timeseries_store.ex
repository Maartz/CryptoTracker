defmodule CryptoTracker.TimeSeriesStore do
  @moduledoc """
  A time series storage manager that handles real-time price data storage in ETS tables
  and automated archiving to ETF files.

  This module provides:
  - Real-time storage of price data in an ETS table for fast access
  - Automatic daily backups of historical data to ETF files
  - Data retention management with a 24-hour sliding window
  - Historical data access through ETF file loading

  ## Architecture

  The storage system works on two levels:
  1. An in-memory ETS table for current data (last 24 hours)
  2. On-disk ETF files for historical data, organized by day

  This dual approach provides:
  - Ultra-fast access to recent data for calculations
  - Efficient storage of historical data
  - Automatic cleanup and archiving

  ## Data Structure

  Each entry in the storage consists of:
  - Key: Unix timestamp (integer, seconds)
  - Value: Price data map containing:
    - price: Current price
    - high_24h: 24-hour high
    - low_24h: 24-hour low
    - volume_24h: 24-hour volume

  ## File Storage

  Historical data is stored in ETF files under the 'priv/price_archives' directory,
  with filenames following the pattern: 'prices_YYYY-MM-DD.etf'
  """

  use GenServer
  require Logger

  @table_name :current_prices
  @archive_dir "priv/price_archives"

  @doc """
  Starts the TimeSeriesStore GenServer process.

  Initializes the ETS table and starts the daily backup scheduler.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Initializes the storage system.

  Creates a new ETS table with ordered_set type for timestamp-based querying
  and schedules the first daily backup.
  """
  def init(_) do
    :ets.new(@table_name, [:named_table, :ordered_set, :public])
    schedule_daily_backup()
    {:ok, %{last_backup_date: Date.utc_today()}}
  end

  @doc """
  Inserts a new price data point into the current ETS table.

  ## Parameters
    - timestamp: Unix timestamp in seconds
    - price_data: Map containing price information

  ## Example
      price_data = %{
        price: 50000.0,
        high_24h: 51000.0,
        low_24h: 49000.0,
        volume_24h: 1000.0
      }
      insert_price(1632150400, price_data)
  """
  def insert_price(timestamp, price_data) do
    :ets.insert(@table_name, {timestamp, price_data})
  end

  @doc """
  Retrieves price data for the last N minutes.

  ## Parameters
    - minutes: Number of minutes to look back

  ## Returns
    List of {timestamp, price_data} tuples for the specified time window

  ## Example
      # Get last 5 minutes of data
      get_last_n_minutes(5)
  """
  def get_last_n_minutes(minutes) do
    cutoff = :os.system_time(:second) - minutes * 60
    # This ETS select query is similar to the following SQL:
    # SELECT timestamp, price_data 
    # FROM current_prices 
    # WHERE timestamp > cutoff;
    #
    # The query structure breaks down as:
    # {{:"$1", :"$2"}}       -> Pattern to match against each record, binding:
    #                              $1 to timestamp
    #                              $2 to price_data
    # [{:>, :"$1", cutoff}]  -> Filter condition: timestamp ($1) must be > cutoff
    # [{{:"$1", :"$2"}}]     -> Return format: {timestamp, price_data} tuples
    #
    # For example, with data:
    # {1705520400, %{price: 40000}}
    # {1705520460, %{price: 41000}}
    # And cutoff = 1705520400
    # Returns: [{1705520460, %{price: 41000}}]
    :ets.select(@table_name, [{{:"$1", :"$2"}, [{:>, :"$1", cutoff}], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Handles the daily backup process.
  Checks if a new day has started and triggers backup if needed.
  """
  def handle_info(:backup_daily, state) do
    today = Date.utc_today()

    if today != state.last_backup_date do
      backup_current_table(state.last_backup_date)
      cleanup_current_table()
      schedule_daily_backup()
      {:noreply, %{state | last_backup_date: today}}
    else
      schedule_daily_backup()
      {:noreply, state}
    end
  end

  @doc """
  Loads historical price data from an ETF file for a specific date.

  ## Parameters
    - date: The Date struct for which to load historical data

  ## Returns
    - {:ok, table_name} on successful load
    - {:error, reason} if loading fails

  ## Example
      # Load data for a specific date
      load_historical_data(~D[2024-01-16])
  """
  def load_historical_data(date) do
    file_name = "#{@archive_dir}/prices_#{Date.to_iso8601(date)}.etf"
    table_name = String.to_atom("prices_#{Date.to_iso8601(date)}")

    case :ets.file2tab(String.to_charlist(file_name)) do
      {:ok, ^table_name} ->
        {:ok, table_name}

      error ->
        {:error, "Failed to load historical data: #{inspect(error)}"}
    end
  end

  defp backup_current_table(date) do
    file_name = "#{@archive_dir}/prices_#{Date.to_iso8601(date)}.etf"
    File.mkdir_p!(@archive_dir)

    case :ets.tab2file(@table_name, String.to_charlist(file_name)) do
      :ok ->
        Logger.info("Successfully backed up prices for #{Date.to_iso8601(date)}")

      {:error, reason} ->
        Logger.error("Failed to backup prices: #{inspect(reason)}")
    end
  end

  defp cleanup_current_table do
    cutoff = :os.system_time(:second) - 24 * 60 * 60
    :ets.select_delete(@table_name, [{{:"$1", :"$2"}, [{:<, :"$1", cutoff}], [true]}])
  end

  defp schedule_daily_backup do
    Process.send_after(self(), :backup_daily, :timer.hours(1))
  end
end

