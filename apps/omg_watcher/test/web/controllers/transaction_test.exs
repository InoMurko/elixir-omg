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

defmodule OMG.Watcher.Web.Controller.TransactionTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OMG.API.Fixtures

  alias OMG.API.Crypto
  alias OMG.Watcher.DB
  alias OMG.Watcher.TestHelper

  @eth Crypto.zero_address()
  @zero_address_hex String.duplicate("00", 20)

  describe "getting transaction by id" do
    @tag fixtures: [:initial_blocks, :alice, :bob]
    test "returns transaction in expected format", %{
      initial_blocks: initial_blocks,
      alice: alice,
      bob: bob
    } do
      {blknum, txindex, txhash, _recovered_tx} = initial_blocks |> hd()

      %DB.Block{timestamp: timestamp, eth_height: eth_height} = DB.Block.get(blknum)
      bob_addr = bob.addr |> TestHelper.to_response_address()
      alice_addr = alice.addr |> TestHelper.to_response_address()
      txhash = Base.encode16(txhash)
      zero_addr = String.duplicate("0", 2 * 20)
      zero_sign = String.duplicate("0", 2 * 65)

      assert %{
               "txid" => ^txhash,
               "txblknum" => ^blknum,
               "txindex" => ^txindex,
               "blknum1" => 1,
               "txindex1" => 0,
               "oindex1" => 0,
               "blknum2" => 0,
               "txindex2" => 0,
               "oindex2" => 0,
               "cur12" => ^zero_addr,
               "newowner1" => ^bob_addr,
               "amount1" => 300,
               "newowner2" => ^zero_addr,
               "amount2" => 0,
               "sig1" => <<_sig1::binary-size(130)>>,
               "sig2" => ^zero_sign,
               "spender1" => ^alice_addr,
               "spender2" => nil,
               "eth_height" => ^eth_height,
               "timestamp" => ^timestamp
             } = TestHelper.success?("/transaction.get", %{"id" => txhash})
    end

    @tag fixtures: [:phoenix_ecto_sandbox]
    test "returns error for non exsiting transaction" do
      txhash = "055673FF58D85BFBF6844BAD62361967C7D19B6A4768CE4B54C687B65728D721"

      assert %{
               "code" => "transaction:not_found",
               "description" => "Transaction doesn't exist for provided search criteria"
             } == TestHelper.no_success?("/transaction.get", %{"id" => txhash})
    end
  end

  describe "getting transactions by address" do
    @tag fixtures: [:alice, :bob, :phoenix_ecto_sandbox]
    test "returns tx that contains requested address as the sender and not recipient", %{
      alice: alice,
      bob: bob
    } do
      OMG.Watcher.DB.EthEvent.insert_deposits([
        %{owner: alice.addr, currency: @eth, amount: 1, blknum: 1}
      ])

      txs = [
        OMG.API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{bob, 300}]),
        OMG.API.TestHelper.create_recovered([{1, 1, 0, bob}], @eth, [{bob, 300}])
      ]

      alice_address = alice.addr |> TestHelper.to_response_address()
      bob_address = bob.addr |> TestHelper.to_response_address()

      expected_result = [
        %{
          "spender1" => alice_address,
          "spender2" => nil,
          "newowner1" => bob_address,
          "newowner2" => @zero_address_hex,
          "eth_height" => 1
        }
      ]

      assert_transactions_filter_by_address_endpoint(txs, expected_result, alice)
    end

    @tag fixtures: [:alice, :bob, :phoenix_ecto_sandbox]
    test "returns tx that contains requested address as both sender & recipient is listed once", %{
      alice: alice,
      bob: bob
    } do
      txs = [
        OMG.API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{alice, 300}]),
        OMG.API.TestHelper.create_recovered([{1, 1, 0, bob}], @eth, [{bob, 300}])
      ]

      alice_address = alice.addr |> TestHelper.to_response_address()

      expected_result = [
        %{
          "spender1" => alice_address,
          "spender2" => nil,
          "newowner1" => alice_address,
          "newowner2" => @zero_address_hex,
          "eth_height" => 1
        }
      ]

      assert_transactions_filter_by_address_endpoint(txs, expected_result, alice)
    end

    @tag fixtures: [:alice, :bob, :phoenix_ecto_sandbox]
    test "returns tx without inputs and contains requested address as recipient", %{
      alice: alice,
      bob: bob
    } do
      txs = [
        OMG.API.TestHelper.create_recovered([], @eth, [{alice, 300}]),
        OMG.API.TestHelper.create_recovered([{1, 1, 0, bob}], @eth, [{bob, 300}])
      ]

      alice_address = alice.addr |> TestHelper.to_response_address()

      expected_result = [
        %{
          "spender1" => nil,
          "spender2" => nil,
          "newowner1" => alice_address,
          "newowner2" => @zero_address_hex,
          "eth_height" => 1
        }
      ]

      assert_transactions_filter_by_address_endpoint(txs, expected_result, alice)
    end

    @tag fixtures: [:alice, :bob, :phoenix_ecto_sandbox]
    test "returns tx without outputs (amount = 0) and contains requested address as sender", %{
      alice: alice,
      bob: bob
    } do
      OMG.Watcher.DB.EthEvent.insert_deposits([
        %{owner: alice.addr, currency: @eth, amount: 1, blknum: 1}
      ])

      txs = [
        OMG.API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{bob, 0}]),
        OMG.API.TestHelper.create_recovered([{1, 1, 0, bob}], @eth, [{bob, 300}])
      ]

      alice_address = alice.addr |> TestHelper.to_response_address()
      bob_address = bob.addr |> TestHelper.to_response_address()

      expected_result = [
        %{
          "spender1" => alice_address,
          "spender2" => nil,
          "newowner1" => bob_address,
          "newowner2" => @zero_address_hex,
          "eth_height" => 1
        }
      ]

      assert_transactions_filter_by_address_endpoint(txs, expected_result, alice)
    end

    @tag fixtures: [:alice, :bob, :phoenix_ecto_sandbox]
    test "returns last 2 transactions", %{
      alice: alice,
      bob: bob
    } do
      OMG.Watcher.DB.EthEvent.insert_deposits([
        %{owner: alice.addr, currency: @eth, amount: 3, blknum: 1}
      ])

      txs = [
        OMG.API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{bob, 3}]),
        OMG.API.TestHelper.create_recovered([{1_000, 0, 0, bob}], @eth, [{alice, 2}]),
        OMG.API.TestHelper.create_recovered([{1_000, 1, 0, alice}], @eth, [{bob, 1}])
      ]

      alice_address = alice.addr |> TestHelper.to_response_address()
      bob_address = bob.addr |> TestHelper.to_response_address()

      expected_result = [
        %{
          "spender1" => alice_address,
          "spender2" => nil,
          "newowner1" => bob_address,
          "newowner2" => @zero_address_hex,
          "eth_height" => 1
        },
        %{
          "spender1" => bob_address,
          "spender2" => nil,
          "newowner1" => alice_address,
          "newowner2" => @zero_address_hex,
          "eth_height" => 1
        }
      ]

      assert_transactions_filter_by_address_endpoint(txs, expected_result, bob, 2)
    end

    defp assert_transactions_filter_by_address_endpoint(
           txs,
           expected_result,
           entity,
           limit \\ 200
         ) do
      {:ok, _} =
        DB.Transaction.update_with(%{
          transactions: txs,
          blknum: 1_000,
          eth_height: 1,
          blkhash: <<?#::256>>,
          timestamp: :os.system_time(:second)
        })

      {:ok, address} = Crypto.encode_address(entity.addr)

      txs = TestHelper.success?("/transaction.all", %{"address" => address, "limit" => limit})

      assert expected_result ==
               txs
               |> Enum.map(&Map.take(&1, ["spender1", "spender2", "newowner1", "newowner2", "eth_height"]))
    end
  end

  describe "getting transactions with limit on number of transactions" do
    @tag fixtures: [:initial_blocks]
    test "limiting all transactions without address filter" do
      txs = TestHelper.success?("/transaction.all", %{"limit" => 2})

      assert [
               %{
                 "txblknum" => 3000,
                 "txindex" => 1,
                 "eth_height" => 1,
                 "timestamp" => 1_540_465_606
               },
               %{
                 "txblknum" => 3000,
                 "txindex" => 0,
                 "eth_height" => 1,
                 "timestamp" => 1_540_465_606
               }
             ] ==
               txs
               |> Enum.map(&Map.take(&1, ["txblknum", "txindex", "eth_height", "timestamp"]))
    end
  end
end
