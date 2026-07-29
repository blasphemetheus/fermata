defmodule Fermata.Model do
  @moduledoc """
  Model construction and the training-numerics policy.

  `build/1` assembles either a small self-contained residual-MLP
  language model in plain Axon (`backbone: :builtin`, the default) or any
  Edifice sequence architecture via `Edifice.Serving.Generate.build_lm/1`
  (`backbone: :decoder_only`, `:mamba`, ...), which since the trainable
  embedding fix (PLAN.md §5.1 gap #1, edifice 73704a4) takes integer
  token IDs and keeps the embedding table inside `Axon.ModelState`.
  Either way the model maps a `"token_ids"` input `[batch, seq_len]` to
  `[batch, seq_len, vocab_size]` logits, so training/generation code is
  backbone-agnostic — as is the policy layer here: bf16 compute, f32
  params, f32 loss.

  Numerics policy (hard-won, see edifice/CLAUDE.md): loss math is ALWAYS
  f32 regardless of network compute precision — `loss/2` casts logits at
  its entry point. Norm layers are excluded from bf16 downcast.
  """

  @norm_ops [:layer_norm, :batch_norm, :group_norm, :rms_norm]

  @doc """
  Build the LM. Options: `:vocab_size` (required), `:seq_len` (required),
  `:backbone` (`:builtin` default, or an Edifice architecture atom such
  as `:decoder_only`), `:embed_dim` (default 64), `:hidden_dim` (default
  128), `:num_layers` (default 2), `:precision` (`:f32` default, or
  `:bf16`). With an Edifice backbone, all further options are forwarded
  to `Edifice.build/2` (e.g. `:num_heads`, `:attention_type`).
  """
  def build(opts) do
    {precision, opts} = Keyword.pop(opts, :precision, :f32)
    {backbone, opts} = Keyword.pop(opts, :backbone, :builtin)

    model =
      case backbone do
        :builtin -> build_builtin(opts)
        arch -> build_edifice(arch, opts)
      end

    case precision do
      :f32 -> model
      :bf16 -> apply_bf16_policy(model)
    end
  end

  defp build_builtin(opts) do
    vocab_size = Keyword.fetch!(opts, :vocab_size)
    seq_len = Keyword.fetch!(opts, :seq_len)
    embed_dim = Keyword.get(opts, :embed_dim, 64)
    hidden_dim = Keyword.get(opts, :hidden_dim, 128)
    num_layers = Keyword.get(opts, :num_layers, 2)

    Axon.input("token_ids", shape: {nil, seq_len})
    |> Axon.embedding(vocab_size, embed_dim, name: "token_embedding")
    |> then(fn x ->
      Enum.reduce(1..num_layers, x, fn i, acc -> block(acc, embed_dim, hidden_dim, i) end)
    end)
    |> Axon.layer_norm(name: "final_norm")
    |> Axon.dense(vocab_size, name: "lm_head", use_bias: false)
  end

  defp build_edifice(arch, opts) do
    vocab_size = Keyword.fetch!(opts, :vocab_size)
    seq_len = Keyword.fetch!(opts, :seq_len)
    embed_dim = Keyword.get(opts, :embed_dim, 64)
    hidden_dim = Keyword.get(opts, :hidden_dim, embed_dim)

    opts
    |> Keyword.drop([:hidden_dim])
    |> Keyword.merge(
      arch: arch,
      vocab_size: vocab_size,
      seq_len: seq_len,
      embed_dim: embed_dim,
      hidden_size: hidden_dim
    )
    |> Edifice.Serving.Generate.build_lm()
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
