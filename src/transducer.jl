
Transducer(::BottomRF) = IdentityTransducer()

function Transducer(rf::Reduction)::Transducer
    if inner(rf) isa BottomRF
        xform(rf)
    else
        Composition(xform(rf), Transducer(inner(rf)))
    end
end

#-----------------------------------------------------------------

@inline Base.:∘(g::Transducer, f::Transducer) = Composition(f, g)
@inline Base.:∘(g::Transducer, f::Composition) = g ∘ f.inner ∘ f.outer
@inline Base.:∘(f::Transducer, ::IdentityTransducer) = f
@inline Base.:∘(::IdentityTransducer, f::Transducer) = f
@inline Base.:∘(f::IdentityTransducer, ::IdentityTransducer) = f
@inline Base.:∘(::IdentityTransducer, f::Composition) = f  # disambiguation

# Base.:(&)(xf1::Transducer, xf2::Transducer) = xf1 ⨟ xf2

#-----------------------------------------------------------------

has(xf::Transducer, ::Type{T}) where {T} = xf isa T
has(xf::Composition, ::Type{T}) where {T} = has(xf.outer, T) || has(xf.inner, T)

Base.broadcastable(xf::Transducer) = Ref(xf)

#-----------------------------------------------------------------

@inline _normalize(xf) = xf
@inline _normalize(xf::Composition{<:Composition}) = xf.inner(xf.outer) # xf.outer |> xf.inner


(xf::Transducer)(itr) = eduction(xf, itr)

"""
    xf'

`xf'(rf₁)` is a shortcut for calling `reducingfunction(xf, rf₁)`.

The adjoint `xf′` of a transducer `xf` is a _reducing
function transform_ `rf₁ -> rf₂`.  That is to say, `xf'` a function
that maps a reducing function `rf₁` to another reducing function
`rf₂`.

# Examples
```jldoctest
julia> using Transducers

julia> y = (Map(inv)'(+))(10, 2)
10.5

julia> y == 10 + inv(2)
true
```
"""
Base.adjoint(xf::Transducer) = ReducingFunctionTransform(xf)
Base.adjoint(rxf::ReducingFunctionTransform) = rxf.xf

(f::ReducingFunctionTransform)(rf; kwargs...) = reducingfunction(f.xf, rf; kwargs...)

@inline Base.:∘(f::ReducingFunctionTransform, g::ReducingFunctionTransform) = (g' ∘ f')'

reducingfunction(xf::Transducer, step) = reduction(xf, step)
reducingfunction(::IdentityTransducer, inner) = ensurerf(inner)

#-----------------------------------------------------------------

abstract type OutputSize end
struct SizeStable <: OutputSize end
struct SizeChanging <: OutputSize end
struct SizeExpansive <: OutputSize end
struct SizeContractive <: OutputSize end

OutputSize(::Type{<:Transducer}) = SizeChanging() # default
OutputSize(::Type{<:AbstractFilter}) = SizeContractive()

OutputSize(::Type{Composition{XO,XI}}) where {XO, XI} =
    combine_outputsize(OutputSize(XO), OutputSize(XI))


combine_outputsize(::SizeStable, ::SizeStable) = SizeStable()
combine_outputsize(::SizeExpansive, ::SizeExpansive) = SizeExpansive()
combine_outputsize(::SizeContractive, ::SizeContractive) = SizeContractive()
combine_outputsize(::OutputSize, ::OutputSize) = SizeChanging()

isexpansive(T#=::Transducer=#) = OutputSize(typeof(T)) === SizeExpansive()
iscontractive(T#=::Transducer=#) = OutputSize(typeof(T)) === SizeContractive()


# For `Eduction` (which stores `Reduction` rather than `Transducer`):
OutputSize(::Type{Reduction{X,I}}) where {X, I <: Reduction} =
    combine_outputsize(OutputSize(X), outputsize(I))
OutputSize(::Type{Reduction{X,I}}) where {X, I} = OutputSize(X)
