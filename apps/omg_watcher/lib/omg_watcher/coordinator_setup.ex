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

defmodule OMG.Watcher.CoordinatorSetup do
  @moduledoc """
  The setup of `OMG.RootChainCoordinator` for the Watcher - configures the relations between different event listeners
  """

  def coordinator_setup do
    deposit_finality_margin = Application.fetch_env!(:omg, :deposit_finality_margin)
    finality_margin = Application.fetch_env!(:omg_watcher, :exit_finality_margin)

    %{
      depositor: [finality_margin: deposit_finality_margin],
      convenience_deposit_processor: [waits_for: [:depositor], finality_margin: finality_margin],
      "Elixir.OMG.Watcher.BlockGetter": [waits_for: [depositor: :no_margin], finality_margin: 0],
      exit_processor: [waits_for: :depositor, finality_margin: finality_margin],
      convenience_exit_processor: [
        waits_for: [:depositor, :"Elixir.OMG.Watcher.BlockGetter"],
        finality_margin: finality_margin
      ],
      exit_finalizer: [
        waits_for: [:depositor, :"Elixir.OMG.Watcher.BlockGetter", :exit_processor],
        finality_margin: finality_margin
      ],
      exit_challenger: [waits_for: :exit_processor, finality_margin: finality_margin],
      in_flight_exit_processor: [waits_for: :depositor, finality_margin: finality_margin],
      piggyback_processor: [waits_for: :in_flight_exit_processor, finality_margin: finality_margin],
      competitor_processor: [waits_for: :in_flight_exit_processor, finality_margin: finality_margin],
      challenges_responds_processor: [waits_for: :competitor_processor, finality_margin: finality_margin],
      piggyback_challenges_processor: [waits_for: :piggyback_processor, finality_margin: finality_margin],
      ife_exit_finalizer: [
        waits_for: [:depositor, :"Elixir.OMG.Watcher.BlockGetter", :in_flight_exit_processor, :piggyback_processor],
        finality_margin: finality_margin
      ]
    }
  end
end
