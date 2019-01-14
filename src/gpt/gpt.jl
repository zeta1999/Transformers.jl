using Flux: @treelike, σ

using ..Basic
using ..Basic: TwoDimArray, ThreeDimArray, onehot

export Gpt, lmloss
export load_gpt_pretrain

struct Gpt
    pe::PositionEmbedding
    ts::Chain
end

@treelike Gpt

#gelu(x) = 0.5x*(1 + tanh(√(2/π)*(x + 0.044715x^3)))
function gelus(x)
    k = x + oftype(x/1, 0.044715) * x^3
    y = oftype(x/1, sqrt(2/π)) * k
    sx = oftype(x/1, 0.5) * x
    z = tanh(y)
    sx * (1 + z)
end

#gelu(x) = x*σ(oftype(x, 1.702)*x)
function gelu(x)
    y = oftype(x/1, 1.702) * x
    z = σ(y)
    x * z
end


function Gpt(size::Int, head::Int, ps::Int, layer::Int; max_len::Int=512, trainable = true, act = gelu)
    rem(size, head) != 0 && error("size not divisible by head")
    Gpt(size, head, div(size, head), ps, layer; max_len=max_len, trainable=trainable, act=act)
end

function Gpt(size::Int, head::Int, hs::Int, ps::Int, layer::Int; max_len::Int=512, trainable = true, act = gelu)
    Gpt(PositionEmbedding(size, max_len; trainable=trainable),
        Chain([Transformer(size, head, hs, ps; future=false, act=act) for i = 1:layer]...))
end

function (gpt::Gpt)(x, mask=nothing)
    pe = gpt.pe(x)
    e = broadcast_add(x, pe)
    t = gpt.ts(e)
    t = mask === nothing ? t : t .* mask
    t #size(t) == (size, seq_len, batch)
end

function lmloss(embed, et, t::TwoDimArray, mask)
    t = t[:, 1:end-1]
    sim = device(embed.embedding') * t
    logcrossentropy(et[:, 2:end], sim, mask[:, 2:end])
end

function lmloss(embed::Embed, et, t::ThreeDimArray, mask)
    t = t[:, 1:end-1, :]
    s = size(t)
    sim = reshape(device(embed.embedding') * reshape(t, s[1], :), length(embed.vocab), s[2:end]...)
    #(vocab, seq_len*batch)
    logcrossentropy(et[:, 2:end, :], sim, mask[:, 2:end, :])
end

function lmloss(gpt::Gpt, embed::Embed, x)
    e, mask = embed(x)
    t = gpt(e, mask)
    lmloss(embed, onehot(embed, x), t, mask)
end

function Base.show(io::IO, gpt::Gpt)
    hs = div(size(gpt.ts[1].mh.iqproj.W)[1], gpt.ts[1].mh.head)
    h, ps = size(gpt.ts[1].pw.dout.W)

    print(io, "Gpt(")
    print(io, "layers=$(length(gpt.ts.layers)), ")
    print(io, "head=$(gpt.ts[1].mh.head), ")
    print(io, "head_size=$(hs), ")
    print(io, "pwffn_size=$(ps), ")
    print(io, "size=$(h))")
end
