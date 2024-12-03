
abstract type Transducer end
abstract type AbstractFilter <: Transducer end


struct Composition{XO <: Transducer, XI <: Transducer} <: Transducer
    outer::XO
    inner::XI
end

struct IdentityTransducer <: Transducer end

# This was <: Function in upstream Transducers, but that is annoying because julia doesn't specialize
# on <: Functions that aren't called. Lets see if we can get away with this not being a <: Function
abstract type AbstractReduction{innertype} end

struct BottomRF{F} <: AbstractReduction{F}
    inner::F
end


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

struct DefaultInit end


struct PrivateState{T, S, R}
    state::S
    result::R

    # Rename constructor to make sure that it is always constructed
    # through the factory function:
    global privatestate(::Type{T}, state::S, result::R) where {
        T <: AbstractReduction,
        S,
        R,
    } =
        new{T, S, R}(state, result)
end
# TODO: make it a tuple-like so that I can return it as-is

ConstructionBase.constructorof(::Type{<:PrivateState{T}}) where T =
    (state, result) -> privatestate(T, state, result)

abstract type Reducible end
abstract type Foldable <: Reducible end
