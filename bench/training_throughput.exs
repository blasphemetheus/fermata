# Measured training throughput for the Phase 1 configuration
# (PLAN.md §5.2: replace the 30-60k tok/s estimate with a number).
#
#   devenv shell -- mix run bench/training_throughput.exs
#
# Env overrides: BENCH_SEQ (1024), BENCH_BATCH (8), BENCH_EMBED (512),
# BENCH_LAYERS (8), BENCH_HEADS (8), BENCH_ITERS (20),
# BENCH_BACKBONE (decoder_only), BENCH_PRECISION (bf16).
#
# Times forward + backward (value_and_grad) per jitted step, synced by
# reading the loss back each iteration; the optimizer update is excluded
# (it is O(params), negligible next to the fwd/bwd at these sizes).

seq_len = String.to_integer(System.get_env("BENCH_SEQ", "1024"))
batch = String.to_integer(System.get_env("BENCH_BATCH", "8"))
embed = String.to_integer(System.get_env("BENCH_EMBED", "512"))
layers = String.to_integer(System.get_env("BENCH_LAYERS", "8"))
heads = String.to_integer(System.get_env("BENCH_HEADS", "8"))
iters = String.to_integer(System.get_env("BENCH_ITERS", "20"))
backbone = String.to_atom(System.get_env("BENCH_BACKBONE", "decoder_only"))
precision = String.to_atom(System.get_env("BENCH_PRECISION", "bf16"))

Nx.default_backend(EXLA.Backend)
Logger.configure(level: :warning)

alias Fermata.{Model, Vocab}

vocab_size = Vocab.size()

model =
  Model.build(
    vocab_size: vocab_size,
    seq_len: seq_len,
    backbone: backbone,
    embed_dim: embed,
    hidden_size: embed,
    num_layers: layers,
    num_heads: heads,
    precision: precision
  )

{init_fn, predict_fn} = Axon.build(model, compiler: EXLA)

params = init_fn.(Nx.template({batch, seq_len}, :s64), Axon.ModelState.empty())

flatten = fn
  %Nx.Tensor{} = t, _self -> [t]
  %{} = map, self -> Enum.flat_map(map, fn {_k, v} -> self.(v, self) end)
  _other, _self -> []
end

param_count =
  params.data |> flatten.(flatten) |> Enum.map(&Nx.size/1) |> Enum.sum()

# Same step shape as test/fermata/model_smoke_test.exs, jitted on EXLA.
step_fn =
  Nx.Defn.jit(
    fn model_state, inputs, targets ->
      trainable = Axon.ModelState.trainable_parameters(model_state)

      Nx.Defn.value_and_grad(trainable, fn tp ->
        logits = predict_fn.(%{model_state | data: tp}, %{"token_ids" => inputs})
        Model.loss(targets, logits)
      end)
    end,
    compiler: EXLA
  )

key = Nx.Random.key(42)
{inputs, key} = Nx.Random.randint(key, 0, vocab_size, shape: {batch, seq_len}, type: :s64)
{targets, _key} = Nx.Random.randint(key, 0, vocab_size, shape: {batch, seq_len}, type: :s64)

IO.puts(
  "backbone=#{backbone} precision=#{precision} params=#{Float.round(param_count / 1.0e6, 1)}M " <>
    "seq=#{seq_len} batch=#{batch} embed=#{embed} layers=#{layers}"
)

# Warmup: first call compiles, second confirms steady state.
{loss, _grads} = step_fn.(params, inputs, targets)
IO.puts("compiled; warmup loss #{Nx.to_number(loss) |> Float.round(3)} (~ln #{vocab_size} = #{Float.round(:math.log(vocab_size), 3)})")
{_loss, _grads} = step_fn.(params, inputs, targets)

{micros, _} =
  :timer.tc(fn ->
    Enum.each(1..iters, fn _ ->
      {loss, _grads} = step_fn.(params, inputs, targets)
      Nx.to_number(loss)
    end)
  end)

seconds = micros / 1.0e6
tokens = batch * seq_len * iters

IO.puts(
  "#{iters} steps in #{Float.round(seconds, 2)}s -> " <>
    "#{Float.round(tokens / seconds / 1000, 1)}k tokens/sec " <>
    "(#{Float.round(seconds * 1000 / iters, 1)} ms/step)"
)
