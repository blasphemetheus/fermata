defmodule Fermata.ModelEdificeTest do
  @moduledoc """
  Wiring test for the Edifice backbone path (PLAN.md §5.1 gap #1, now
  fixed upstream): `Fermata.Model.build(backbone: :decoder_only)` must
  produce a model that takes integer token IDs, holds its embedding
  table inside `Axon.ModelState`, and passes gradients through it.
  Tiny dims, f32, binary backend — this checks plumbing, not learning.
  """
  use ExUnit.Case, async: true

  alias Fermata.Model

  @vocab_size 32
  @seq_len 8
  @batch 2

  defp build_model do
    Model.build(
      vocab_size: @vocab_size,
      seq_len: @seq_len,
      backbone: :decoder_only,
      embed_dim: 8,
      hidden_dim: 8,
      num_layers: 1,
      num_heads: 2,
      num_kv_heads: 2
    )
  end

  test "edifice backbone takes token_ids and embeds inside the model" do
    model = build_model()

    assert Map.has_key?(Axon.get_inputs(model), "token_ids")

    {init_fn, predict_fn} = Axon.build(model, compiler: Nx.Defn.Evaluator)

    params =
      init_fn.(
        %{"token_ids" => Nx.template({@batch, @seq_len}, :s64)},
        Axon.ModelState.empty()
      )

    assert %{"token_embedding" => %{"kernel" => kernel}} = params.data
    assert Nx.shape(kernel) == {@vocab_size, 8}

    tokens = Nx.remainder(Nx.iota({@batch, @seq_len}), @vocab_size)
    logits = predict_fn.(params, %{"token_ids" => tokens})
    assert Nx.shape(logits) == {@batch, @seq_len, @vocab_size}
  end

  test "gradients flow through the embedding table" do
    model = build_model()
    {init_fn, predict_fn} = Axon.build(model, compiler: Nx.Defn.Evaluator)

    params =
      init_fn.(
        %{"token_ids" => Nx.template({@batch, @seq_len}, :s64)},
        Axon.ModelState.empty()
      )

    tokens = Nx.remainder(Nx.iota({@batch, @seq_len}), @vocab_size)
    targets = Nx.remainder(Nx.add(tokens, 1), @vocab_size)

    grad_fn =
      Nx.Defn.jit(
        fn model_state, inputs, targets ->
          trainable = Axon.ModelState.trainable_parameters(model_state)

          Nx.Defn.grad(trainable, fn tp ->
            logits = predict_fn.(%{model_state | data: tp}, %{"token_ids" => inputs})
            Model.loss(targets, logits)
          end)
        end,
        compiler: Nx.Defn.Evaluator
      )

    grads = grad_fn.(params, tokens, targets)

    grad_magnitude =
      grads["token_embedding"]["kernel"] |> Nx.abs() |> Nx.sum() |> Nx.to_number()

    assert grad_magnitude > 0.0,
           "embedding gradient is identically zero — table is not training"
  end
end
