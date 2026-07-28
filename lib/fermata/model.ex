defmodule Fermata.Model do
  @moduledoc """
  Model construction and the training-numerics policy.

  `build/1` currently assembles a small self-contained residual-MLP
  language model in plain Axon: token embedding → N pre-norm residual
  blocks → final norm → LM head. It exists to pin down the *policy*
  layer — bf16 compute, f32 params, f32 loss — before the real backbone
  arrives. The production path swaps the block stack for an Edifice
  backbone once `Edifice.Serving.Generate.build_lm/1` gains a trainable
  embedding (PLAN.md §5.1 gap #1); the policy code here is
  backbone-agnostic.

  Numerics policy (hard-won, see edifice/CLAUDE.md): loss math is ALWAYS
  f32 regardless of network compute precision — `loss/2` casts logits at
  its entry point. Norm layers are excluded from bf16 downcast.
  """

  @norm_ops [:layer_norm, :batch_norm, :group_norm, :rms_norm]

  @doc """
  Build the LM. Options: `:vocab_size` (required), `:seq_len` (required),
  `:embed_dim` (default 64), `:hidden_dim` (default 128), `:num_layers`
  (default 2), `:precision` (`:f32` default, or `:bf16`).
  """
  def build(opts) do
    vocab_size = Keyword.fetch!(opts, :vocab_size)
    seq_len = Keyword.fetch!(opts, :seq_len)
    embed_dim = Keyword.get(opts, :embed_dim, 64)
    hidden_dim = Keyword.get(opts, :hidden_dim, 128)
    num_layers = Keyword.get(opts, :num_layers, 2)

    model =
      Axon.input("tokens", shape: {nil, seq_len})
      |> Axon.embedding(vocab_size, embed_dim, name: "token_embedding")
      |> then(fn x ->
        Enum.reduce(1..num_layers, x, fn i, acc -> block(acc, embed_dim, hidden_dim, i) end)
      end)
      |> Axon.layer_norm(name: "final_norm")
      |> Axon.dense(vocab_size, name: "lm_head", use_bias: false)

    case Keyword.get(opts, :precision, :f32) do
      :f32 -> model
      :bf16 -> apply_bf16_policy(model)
    end
  end

  defp block(x, embed_dim, hidden_dim, i) do
    x
    |> Axon.layer_norm(name: "block_#{i}_norm")
    |> Axon.dense(hidden_dim, activation: :gelu, name: "block_#{i}_up")
    |> Axon.dense(embed_dim, name: "block_#{i}_down")
    |> Axon.add(x, name: "block_#{i}_residual")
  end

  defp apply_bf16_policy(model) do
    policy =
      Axon.MixedPrecision.create_policy(
        params: {:f, 32},
        compute: {:bf, 16},
        output: {:f, 32}
      )

    Axon.MixedPrecision.apply_policy(model, policy, fn %Axon.Node{op: op} ->
      op not in @norm_ops
    end)
  end

  @doc """
  Next-token cross-entropy. Logits are cast to f32 before any loss math,
  whatever precision the network computed in.
  """
  def loss(targets, logits) do
    # sparse mode expects class indices with a trailing size-1 axis
    targets = Nx.new_axis(targets, -1)

    logits
    |> Nx.as_type({:f, 32})
    |> then(
      &Axon.Losses.categorical_cross_entropy(targets, &1,
        sparse: true,
        from_logits: true,
        reduction: :mean
      )
    )
  end
end
