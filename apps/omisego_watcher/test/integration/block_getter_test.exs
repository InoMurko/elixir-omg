defmodule OmiseGOWatcher.BlockGetterTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OmiseGO.API.Fixtures
  use Plug.Test
  use Phoenix.ChannelTest

  alias OmiseGO.API
  alias OmiseGO.API.Block
  alias OmiseGO.API.TestHelper, as: API_Helper
  alias OmiseGO.API.State.Transaction
  alias OmiseGO.Eth
  alias OmiseGO.JSONRPC.Client
  alias OmiseGOWatcherWeb.AddressChannel
  alias OmiseGOWatcher.TestHelper, as: Test
  alias OmiseGOWatcher.Eventer.Event

  @moduletag :integration

  @timeout 20_000
  @block_offset 1_000_000_000
  @zero_address <<0::size(160)>>

  @endpoint OmiseGOWatcherWeb.Endpoint

  defp deposit_to_child_chain(to, value, config) do
    {:ok, destiny_enc} = Eth.DevHelpers.import_unlock_fund(to)
    {:ok, deposit_tx_hash} = Eth.DevHelpers.deposit(value, 0, destiny_enc, config.contract_addr)
    {:ok, receipt} = Eth.WaitFor.eth_receipt(deposit_tx_hash)
    deposit_blknum = Eth.DevHelpers.deposit_blknum_from_receipt(receipt)

    post_deposit_child_block =
      deposit_blknum - 1 + (config.ethereum_event_block_finality_margin + 1) * config.child_block_interval

    {:ok, _} = Eth.DevHelpers.wait_for_current_child_block(post_deposit_child_block, true, 60_000, config.contract_addr)

    deposit_blknum
  end

  @tag fixtures: [:watcher_sandbox, :config_map, :geth, :child_chain, :root_chain_contract_config, :alice, :bob]
  test "get the blocks from child chain after transaction and start exit",
       %{config_map: config_map, alice: alice, bob: bob} do
    alice_address = "0x" <> Base.encode16(alice.addr, case: :lower)

    {:ok, _, _socket} = subscribe_and_join(socket(), AddressChannel, "address:" <> alice_address)

    {:ok, _pid} =
      GenServer.start_link(
        OmiseGOWatcher.BlockGetter,
        %{contract_address: config_map.contract_addr},
        name: BlockGetter
      )

    deposit_blknum = deposit_to_child_chain(alice, 10, config_map)
    raw_tx = Transaction.new([{deposit_blknum, 0, 0}], Transaction.zero_address(), [{alice.addr, 7}, {bob.addr, 3}])
    tx = raw_tx |> Transaction.sign(alice.priv, <<>>) |> Transaction.Signed.encode()

    {:ok, %{"blknum" => block_nr}} = Client.call(:submit, %{transaction: tx})

    # wait for BlockGetter get the block
    fn ->
      Eth.WaitFor.repeat_until_ok(fn ->
        # TODO use event system
        case GenServer.call(BlockGetter, :get_height, 10_000) < block_nr do
          true -> :repeat
          false -> {:ok, block_nr}
        end
      end)
    end
    |> Task.async()
    |> Task.await(@timeout)

    encode_tx = Client.encode(tx)

    assert [%{"amount" => 3, "blknum" => block_nr, "oindex" => 0, "txindex" => 0, "txbytes" => encode_tx}] ==
             get_utxo(bob)

    assert [%{"amount" => 7, "blknum" => block_nr, "oindex" => 0, "txindex" => 0, "txbytes" => encode_tx}] ==
             get_utxo(alice)

    {:ok, recovered_tx} = API.Core.recover_tx(tx)
    assert_push("address_received", %Event.AddressReceived{tx: ^recovered_tx})

    %{
      utxo_pos: utxo_pos,
      tx_bytes: tx_bytes,
      proof: proof,
      sigs: sigs
    } = compose_utxo_exit(block_nr, 0, 0)

    {:ok, txhash} =
      Eth.start_exit(
        utxo_pos * @block_offset,
        tx_bytes,
        proof,
        sigs,
        1,
        alice_address,
        config_map.contract_addr
      )

    {:ok, _} = Eth.WaitFor.eth_receipt(txhash, @timeout)

    {:ok, height} = Eth.get_ethereum_height()

    assert {:ok, [%{amount: 7, blknum: block_nr, oindex: 0, owner: alice_address, txindex: 0, token: @zero_address}]} ==
             Eth.get_exits(0, height, config_map.contract_addr)
  end

  @tag fixtures: [:watcher_sandbox, :alice]
  test "try consume block with invalid transaction", %{alice: alice} do
    assert {:error, :amounts_dont_add_up} ==
             OmiseGOWatcher.BlockGetter.consume_block(%Block{
               transactions: [API_Helper.create_recovered([], Transaction.zero_address(), [{alice, 1200}])],
               number: 1_000
             })

    assert {:error, :utxo_not_found} ==
             OmiseGOWatcher.BlockGetter.consume_block(%Block{
               transactions: [
                 API_Helper.create_recovered([{1_000, 0, 0, alice}], Transaction.zero_address(), [{alice, 1200}])
               ],
               number: 1_000
             })
  end

  @tag fixtures: [:watcher_sandbox, :alice, :carol, :bob]
  test "consume block with valid transactions", %{alice: alice, carol: carol, bob: bob} do
    OmiseGOWatcher.BlockGetter.consume_block(%Block{
      transactions: [],
      number: 1_000
    })

    assert :ok ==
             OmiseGO.API.State.deposit([
               %{owner: alice.addr, currency: Transaction.zero_address(), amount: 1_000, blknum: 1_001},
               %{owner: bob.addr, currency: Transaction.zero_address(), amount: 1_000, blknum: 1_002}
             ])

    assert :ok ==
             OmiseGOWatcher.BlockGetter.consume_block(%Block{
               transactions: [
                 API_Helper.create_recovered(
                   [{1_001, 0, 0, alice}],
                   Transaction.zero_address(),
                   [{alice, 700}, {carol, 200}]
                 ),
                 API_Helper.create_recovered(
                   [{1_002, 0, 0, bob}],
                   Transaction.zero_address(),
                   [{carol, 500}, {bob, 400}]
                 )
               ],
               number: 2_000
             })

    assert [%{"amount" => 700, "blknum" => 2000, "oindex" => 0, "txindex" => 0}] = get_utxo(alice)
    assert [%{"amount" => 400, "blknum" => 2000, "oindex" => 0, "txindex" => 1}] = get_utxo(bob)

    assert [
             %{"amount" => 200, "blknum" => 2000, "oindex" => 0, "txindex" => 0},
             %{"amount" => 500, "blknum" => 2000, "oindex" => 0, "txindex" => 1}
           ] = get_utxo(carol)
  end

  defp get_utxo(%{addr: address}) do
    decoded_resp = Test.rest_call(:get, "account/utxo?address=#{Client.encode(address)}")
    decoded_resp["utxos"]
  end

  defp compose_utxo_exit(block_height, txindex, oindex) do
    decoded_resp =
      Test.rest_call(:get, "account/utxo/compose_exit?block_height=#{block_height}&txindex=#{txindex}&oindex=#{oindex}")

    {:ok, tx_bytes} = Client.decode(:bitstring, decoded_resp["tx_bytes"])
    {:ok, proof} = Client.decode(:bitstring, decoded_resp["proof"])
    {:ok, sigs} = Client.decode(:bitstring, decoded_resp["sigs"])

    %{
      utxo_pos: decoded_resp["utxo_pos"],
      tx_bytes: tx_bytes,
      proof: proof,
      sigs: sigs
    }
  end
end