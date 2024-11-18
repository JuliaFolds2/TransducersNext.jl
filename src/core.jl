#-----------------------------------------------------------------

abstract type Transducer end
abstract type AbstractFilter <: Transducer end

struct Composition{XO <: Transducer, XI <: Transducer} <: Transducer
    outer::XO
    inner::XI
end

struct IdentityTransducer <: Transducer end

has(xf::Transducer, ::Type{T}) where {T} = xf isa T
has(xf::Composition, ::Type{T}) where {T} = has(xf.outer, T) || has(xf.inner, T)

Base.broadcastable(xf::Transducer) = Ref(xf)

#-----------------------------------------------------------------

@inline next(f, result, input) = _next(f, result, input)
@inline _next(f, result, input) = f(result, input)

abstract type AbstractReduction{innertype} <: Function end
@inline (rf::AbstractReduction)(state, input) = next(rf, state, input)
InnerType(::Type{<:AbstractReduction{T}}) where T = T
ConstructionBase.constructorof(::Type{T}) where {T <: AbstractReduction} = T

inner(rf::AbstractReduction) = rf.inner
xform(rf::AbstractReduction) = rf.xform
has(rf::AbstractReduction, T::Type{<:Transducer}) = has(Transducer(rf), T)

struct BottomRF{F} <: AbstractReduction{F}
    inner::F
end

ensurerf(rf::AbstractReduction) = rf
ensurerf(f) = BottomRF(f)

start(rf::BottomRF, result) = start(inner(rf), result)
@inline next(rf::BottomRF, result, input) = next(inner(rf), result, input)

# @inline completebasecase(rf::BottomRF, result) = completebasecase(inner(rf), result)
# complete(rf::BottomRF, result) = complete(inner(rf), result)
combine(rf::BottomRF, a, b) = combine(inner(rf), a, b)

Transducer(::BottomRF) = IdentityTransducer()

as(rf::T, ::Type{T}) where T = rf
as(rf, ::Type{T}) where {T} = as(inner(rf), T)


struct Reduction{X <: Transducer, I} <: AbstractReduction{I}
    xform::X
    inner::I

    Reduction{X, I}(xf, inner) where {X, I} = new{X, I}(xf, inner)

    function Reduction(xf::X, inner::I) where {X <: Transducer, I}
        if I <: AbstractReduction
            new{X, I}(xf, inner)
        else
            rf = ensurerf(inner)
            new{X, typeof(rf)}(xf, rf)
        end
    end
end

Base.:(==)(r1::Reduction, r2::Reduction) = (r1.xform == r2.xform) && (r1.inner == r2.inner)

reduction(rf, xf) = Reduction(rf, xf)
reduction(::IdentityTransducer, inner)::AbstractReduction = ensurerf(inner)

prependxf(rf::AbstractReduction, xf) = reduction(xf, rf)
setinner(rf::Reduction, inner) = reduction(xform(rf), inner)
setxform(rf::Reduction, xform) = reduction(xform, inner(rf))

function Transducer(rf::Reduction)::Transducer
    if inner(rf) isa BottomRF
        xform(rf)
    else
        Composition(xform(rf), Transducer(inner(rf)))
    end
end

const R_{X} = Reduction{<:X}

@inline function reduction(xf_::Composition, f)
    xf = _normalize(xf_)
    # @assert !(xf.outer isa Composition)
    return reduction(xf.outer, reduction(xf.inner, f))
end
@inline _normalize(xf) = xf
@inline _normalize(xf::Composition{<:Composition}) = xf.inner(xf.outer) # xf.outer |> xf.inner

"""
    combine(rf, a, b)

Combine the results of two reductions (`a` and `b`) using the innermost reducing function of `rf`.

This is necessary whenever a reduction is split up or reassociated. E.g. imagine some `fold(+, Map(sin), [1,2,3,4])`.
This can be written as
```julia
rf = Map(sin)'(+)
rf(rf(rf(1, 2), 3), 4)
```
if the fold is sequential, but a non-sequential fold *cannot* do
```julia
rf = Map(sin)'(+)
a = rf(1, 2)
b = rf(3, 4)
rf(a, b) # wrong
```
because then `sin` would end up getting applied too many times!

Instead, the arguments must be combined as
```julia
rf = Map(sin)'(+)
a = rf(1, 2)
b = rf(3, 4)
+(a, b) # right
```

In upstream Transducers.jl, stateful transducers are supposed to overload this function to teach transducers.jl how to combine the inner states of the transducers.
"""
function combine(f, a, b)
    if a isa DefaultInit
        b
    elseif b isa DefaultInit
        a
    else
        f(a, b)
    end
end
combine(rf::Reduction, a, b) = combine(inner(rf), a, b)


@inline Base.:∘(g::Transducer, f::Transducer) = Composition(f, g)
@inline Base.:∘(g::Transducer, f::Composition) = g ∘ f.inner ∘ f.outer
@inline Base.:∘(f::Transducer, ::IdentityTransducer) = f
@inline Base.:∘(::IdentityTransducer, f::Transducer) = f
@inline Base.:∘(f::IdentityTransducer, ::IdentityTransducer) = f
@inline Base.:∘(::IdentityTransducer, f::Composition) = f  # disambiguation


(xf::Transducer)(itr) = eduction(xf, itr)

"""
    ReducingFunctionTransform(xf)

This is a "true" transducer in the sense introduced in Clojure. This is an object that transforms reducing functions using the enclosed transducer. This type of object should be created using `xf'` or `adjoint(xf)`.

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
struct ReducingFunctionTransform{T <: Transducer} <: Function
    xf::T
end

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


"""
    reform(rf, f)

Reset "bottom" reducing function of `rf` to `f`.
"""
reform(rf::Reduction, f) = reducingfunction(xform(rf), reform(inner(rf), f))
reform(rf::BottomRF, f) = BottomRF(reform(inner(rf), f))
reform(::Any, f) = f

#-----------------------------------------------------------------


"""
    Transducers.start(rf::R_{X}, state)

This is an optional interface for a transducer.  Default
implementation just calls `start` of the inner reducing function; i.e.,

```julia
start(rf::Reduction, result) = start(inner(rf), result)
```

If the transducer `X` is stateful, it can "bundle" its private state
with `wrap`:

```julia
start(rf::R_{X}, result) = wrap(rf, PRIVATE_STATE, start(inner(rf), result))
```

where `PRIVATE_STATE` is an initial value for the private state that
can be used inside [`next`](@ref) via [`wrapping`](@ref).

See [`Take`](@ref), [`PartitionBy`](@ref), etc. for real-world examples.

Side notes: There is no related API in Clojure's Transducers.
Transducers.jl uses it to implement stateful transducers using "pure"
functions.  The idea is based on a slightly different approach taken
in C++ Transducer library [atria](https://github.com/AbletonAG/atria).
"""
start(rf, init) = init
start(rf::Reduction, result) = start(inner(rf), result)
# start(rf::R_{AbstractFilter}, result) = start(inner(rf), result) # Why does this method exist?

# #-----------------------------------------------------------------
# Not yet implemented

# """
#     Transducers.complete(rf::R_{X}, state)

# This is an optional interface for a transducer.  If transducer `X` has
# some internal state, this is the last chance to "flush" the result.

# See [`PartitionBy`](@ref), etc. for real-world examples.

# If `start(rf::R_{X}, state)` is defined, `complete` **must** unwarp
# `state` before returning `state` to the outer reducing function.
# """
# complete(f, result) = f(result)
# function complete(rf::AbstractReduction, result)
#     # Not using dispatch to avoid ambiguity
#     if ownsstate(rf, result)
#         complete_stateful_error(rf)
#     else
#         complete(inner(rf), result)
#     end
# end
# @noinline function complete_stateful_error(rf)
#     error("`complete` for ", typeof(xform(rf)), " is not defined, ",
#           "it is mandatory for reductions with private state to implement ",
#           "a `complete` method.")
# end 

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
# This used to be `outputsize` I'm changing it to OutputSize
OutputSize(::Type{Reduction{X,I}}) where {X, I <: Reduction} =
    combine_outputsize(OutputSize(X), outputsize(I))
OutputSize(::Type{Reduction{X,I}}) where {X, I} = OutputSize(X)

#-----------------------------------------------------------------

"""
    right([l, ]r) -> r

It is simply defined as

```julia
right(l, r) = r
right(r) = r
```

This function is meant to be used as `step` argument for
[`foldl`](@ref) etc. for extracting the last output of the
transducers.

# Examples
```jldoctest
julia> using Transducers

julia> foldl(right, Take(5), 1:10)
5

julia> foldl(right, Drop(5), 1:3; init=0)  # using `init` as the default value
0
```
"""
right(l, r) = r
right(r) = r

#-----------------------------------------------------------------


abstract type Reducible end
abstract type Foldable <: Reducible end
Base.IteratorSize(::Type{<:Reducible}) = Base.SizeUnknown()

"""
   asfoldable(x) -> foldable
   
By default, this function does nothing, but it can be overloaded to convert an input into another type before reducing over it.
This allows one to implement a foldable in terms of transducers over an existing type. For instance,

```julia
struct VectorOfVectors{T}
   v::Vector{Vector{T}}
end

Transducers.asfoldable(vov::VectorOfVectors{T}) = vov.v |> Cat()
```
Now we can do things like
```julia
julia> foldxl(+, VectorOfVectors([[1,2], [3, 4]]))
10
```
"""
asfoldable(x) = x


struct DefaultInit end
_next(rf, ::DefaultInit, val) = val

#-----------------------------------------------------------------

reducingfunction(xf::Transducer, step) = reduction(xf, step)
reducingfunction(::IdentityTransducer, inner) = ensurerf(inner)
