defmodule Fermata.ModelSmokeTest do
  @moduledoc """
  bf16 training-numerics smoke test (PLAN.md Phase 0).

  Trains a tiny LM for a few dozen steps on real chorale tokens under the
  bf16 mixed-precision policy and asserts every loss and every parameter
  stays finite, and that loss actually decreases. Runs on the pure-Elixir
  binary backend, so it is slow per-FLOP but tiny — the point is to
  exercise the exact policy wiring (bf16 compute / f32 params / f32 loss)
  that a week-long 5090 run will depend on, where a NaN at step 400k is
  how you find out the policy was wrong.
  """
  use ExUnit.Case, async: false

  # BinaryBackend emulates bf16 in software, so keep everything tiny.
  @moduletag timeout: 180_000

  alias Fermata.{Fixtures.Chorale, Model, Tokenizer}

  @seq_len 8
  @batch 2
  @steps 10

  test "bf16 policy trains without NaN/Inf and the loss goes down" do
    ids = Tokenizer.encode_ids!(Chorale.score())
    vocab_size = Fermata.Vocab.size()

    model =
      Model.build(
        vocab_size: vocab_size,
        seq_len: @seq_len,
        embed_dim: 8,
        hidden_dim: 16,
        num_layers: 2,
        precision: :bf16
      )

    {init_fn, predict_fn} = Axon.build(model, compiler: Nx.Defn.Evaluator)

    params =
      init_fn.(Nx.template({@batch, @seq_len}, :s64), Axon.ModelState.empty())

    {opt_init, opt_update} = Polaris.Optimizers.adamw(learning_rate: 1.0e-2)
    opt_state = opt_init.(params.data)

    # The whole step is one jitted function and the model state is a
    # traced argument — closing over concrete tensors inside
    # value_and_grad breaks Axon's layer compilation. This mirrors
    # Axon.Loop.train_step: differentiate over trainable_parameters and
    # graft them back into the model state inside the objective.
    step_fn =
      Nx.Defn.jit(
        fn model_state, inputs, targets ->
          trainable = Axon.ModelState.trainable_parameters(model_state)

          Nx.Defn.value_and_grad(trainable, fn tp ->
            logits = predict_fn.(%{model_state | data: tp}, %{"token_ids" => inputs})
            Model.loss(targets, logits)
          end)
        end,
        compiler: Nx.Defn.Evaluator
      )

    windows = windows(ids)

    {_params, _opt_state, losses} =
      Enum.reduce(1..@steps, {params, opt_state, []}, fn step, {params, opt_state, losses} ->
        {inputs, targets} = batch_at(windows, step)

        {loss, grads} = step_fn.(params, inputs, targets)

        assert finite?(loss), "loss became non-finite at step #{step}"

        {updates, opt_state} = opt_update.(grads, opt_state, params.data)
        # Not Polaris.Updates.apply_updates/2: its optional `state`
        # defaults to nil, which nx 0.13's jit arg traversal rejects
        # (Polaris 0.1 predates that check).
        data = apply_updates(params.data, updates)

        assert all_finite?(data), "parameters became non-finite at step #{step}"

        {%{params | data: data}, opt_state, [Nx.to_number(loss) | losses]}
      end)

    losses = Enum.reverse(losses)
    first_avg = losses |> Enum.take(3) |> average()
    last_avg = losses |> Enum.take(-3) |> average()

    assert last_avg < first_avg,
           "loss did not decrease: first 3 avg #{first_avg}, last 3 avg #{last_avg}"
  end

  # Overlapping (input, target) next-token windows over the chorale ids.
  defp windows(ids) do
    ids
    |> Enum.chunk_every(@seq_len + 1, 1, :discard)
    |> Enum.map(fn chunk ->
      {Enum.take(chunk, @seq_len), Enum.drop(chunk, 1)}
    end)
  end

  defp batch_at(windows, step) do
    picked =
      for i <- 0..(@batch - 1) do
        Enum.at(windows, rem(step * @batch + i, length(windows)))
      end

    inputs = Nx.tensor(Enum.map(picked, &elem(&1, 0)), type: :s64)
    targets = Nx.tensor(Enum.map(picked, &elem(&1, 1)), type: :s64)
    {inputs, targets}
  end

  defp finite?(tensor) do
    tensor |> Nx.is_nan() |> Nx.any() |> Nx.to_number() == 0 and
      tensor |> Nx.is_infinity() |> Nx.any() |> Nx.to_number() == 0
  end

  defp all_finite?(data) do
    data
    |> flatten_tensors()
    |> Enum.all?(&finite?/1)
  end

  defp apply_updates(%Nx.Tensor{} = param, %Nx.Tensor{} = update), do: Nx.add(param, update)

  defp apply_updates(%{} = params, %{} = updates),
    do: Map.new(params, fn {k, v} -> {k, apply_updates(v, Map.fetch!(updates, k))} end)

  defp flatten_tensors(%Nx.Tensor{} = t), do: [t]
  defp flatten_tensors(%{} = map), do: Enum.flat_map(map, fn {_k, v} -> flatten_tensors(v) end)
  defp flatten_tensors(_other), do: []

  defp average(list), do: Enum.sum(list) / length(list)
end
