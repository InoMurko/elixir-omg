# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.API.EthereumEventListener.Core do
  @moduledoc """
  Functional core of event listener
  """
  alias OMG.API.RootChainCoordinator.SyncData

  defstruct synced_height_update_key: nil,
            service_name: nil,
            # what's being exchanged with RootChainCoorinator - the point in Eth blockchain until where it did process
            synced_height: 0,
            cached: %{
              data: [],
              request_max_size: 1000,
              # until which height the events have been pulled and cached
              events_upper_bound: 0
            }

  @type event :: %{eth_height: non_neg_integer()}

  @type t() :: %__MODULE__{
          synced_height_update_key: atom(),
          service_name: atom(),
          cached: %{
            data: list(event),
            request_max_size: pos_integer(),
            events_upper_bound: non_neg_integer()
          }
        }

  @spec init(atom(), atom(), non_neg_integer(), non_neg_integer()) :: t() | {:error, :invalid_init}
  def init(update_key, service_name, last_synced_ethereum_height, request_max_size \\ 1000)

  def init(_, _, _, 0), do: {:error, :invalid_init}

  def init(update_key, service_name, last_synced_ethereum_height, request_max_size) do
    %__MODULE__{
      synced_height_update_key: update_key,
      synced_height: last_synced_ethereum_height,
      service_name: service_name,
      cached: %{
        request_max_size: request_max_size,
        data: [],
        events_upper_bound: last_synced_ethereum_height
      }
    }
  end

  @doc """
  Returns range Ethereum height to download
  """
  @spec get_events_range_for_download(t(), SyncData.t()) ::
          {:dont_fetch_events, t()} | {:get_events, {non_neg_integer, non_neg_integer}, t()}
  def get_events_range_for_download(%__MODULE__{cached: %{events_upper_bound: upper}} = state, %SyncData{
        sync_height: sync_height
      })
      when sync_height <= upper,
      do: {:dont_fetch_events, state}

  def get_events_range_for_download(
        %__MODULE__{
          cached: %{request_max_size: request_max_size, events_upper_bound: old_upper_bound} = cached_data
        } = state,
        %SyncData{root_chain_height: root_chain_height, sync_height: sync_height}
      ) do
    # grab as much as allowed, but not higher than current root_chain_height and at least as much as needed to sync
    # NOTE: both root_chain_height and sync_height are assumed to have any required finality margins applied by caller
    next_upper_bound =
      min(root_chain_height, old_upper_bound + request_max_size)
      |> max(sync_height)

    new_state = %__MODULE__{
      state
      | cached: %{cached_data | events_upper_bound: next_upper_bound}
    }

    {:get_events, {old_upper_bound + 1, next_upper_bound}, new_state}
  end

  @spec add_new_events(t(), list(event)) :: t()
  def add_new_events(
        %__MODULE__{cached: %{data: data} = cached_data} = state,
        new_events
      ) do
    %__MODULE__{state | cached: %{cached_data | data: data ++ new_events}}
  end

  @spec get_events(t(), non_neg_integer) :: {:ok, list(event), list(), non_neg_integer, t()}
  def get_events(
        %__MODULE__{
          synced_height_update_key: update_key,
          cached: %{data: data} = cached_data
        } = state,
        sync_height
      ) do
    sync = sync_height
    {events, new_data} = Enum.split_while(data, fn %{eth_height: height} -> height <= sync end)

    db_update = [{:put, update_key, sync_height}]
    new_state = %__MODULE__{state | synced_height: sync_height, cached: %{cached_data | data: new_data}}

    {:ok, events, db_update, sync_height, new_state}
  end
end
