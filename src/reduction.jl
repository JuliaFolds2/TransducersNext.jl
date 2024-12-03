const R_{X} = Reduction{<:X}
Base.:(==)(r1::Reduction, r2::Reduction) = (r1.xform == r2.xform) && (r1.inner == r2.inner)
#-----------------------------------------------------------------

@inline next(f::F, result, input)  where {F} = _next(f, result, input)
@inline next(rf::BottomRF{F}, result, input) where {F} = next(inner(rf), result, input)

@inline _next(rf, ::DefaultInit, val) = val
@inline _next(f::F, result, input) where {F} = f(result, input)

@inline (rf::AbstractReduction)(state, input) = next(rf, state, input)

InnerType(::Type{<:AbstractReduction{T}}) where T = T
ConstructionBase.constructorof(::Type{T}) where {T <: AbstractReduction} = T

inner(rf::R) where {R <: AbstractReduction} = rf.inner
xform(rf::R) where {R <: AbstractReduction} = rf.xform
has(rf::AbstractReduction, T::Type{<:Transducer}) = has(Transducer(rf), T)


ensurerf(rf::AbstractReduction) = rf
ensurerf(f) = BottomRF(f)

start(rf::BottomRF, result) = start(inner(rf), result)


as(rf::T, ::Type{T}) where T = rf
as(rf, ::Type{T}) where {T} = as(inner(rf), T)


reduction(rf, xf) = Reduction(rf, xf)
reduction(::IdentityTransducer, inner)::AbstractReduction = ensurerf(inner)
@inline function reduction(xf_::Composition, f)
    xf = _normalize(xf_)
    # @assert !(xf.outer isa Composition)
    return reduction(xf.outer, reduction(xf.inner, f))
end

prependxf(rf::AbstractReduction, xf) = reduction(xf, rf)
setinner(rf::Reduction, inner) = reduction(xform(rf), inner)
setxform(rf::Reduction, xform) = reduction(xform, inner(rf))


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
function combine(rf::Reduction, a, b)
    if ownsstate(rf, a)
        error("Stateful transducer ", xform(rf), " does not support `combine`")
    elseif ownsstate(rf, b)
        error("""
        Some thing went wrong in two ways:
        * `combine(rf, a, b)` is called but type of `a` and `b` are different.
        * `xform(rf) = $(xform(rf))` is stateful and does not support `combine`.
        """)
    else
        combine(inner(rf), a, b)
    end
end


"""
    reform(rf, f)

Reset "bottom" reducing function of `rf` to `f`.
"""
reform(rf::Reduction, f) = reducingfunction(xform(rf), reform(inner(rf), f))
reform(rf::BottomRF, f) = BottomRF(reform(inner(rf), f))
reform(::Any, f) = f


