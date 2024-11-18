#-----------------------------------------------------------------

# https://clojure.github.io/clojure/clojure.core-api.html#clojure.core/map
# https://clojuredocs.org/clojure.core/map
"""
    Map(f)

Apply unary function `f` to each input and pass the result to the
inner reducing step.

$(_thx_clj("map"))

# Examples
```jldoctest
julia> using Transducers

julia> collect(Map(x -> 2x), 1:3)
3-element Vector{Int64}:
 2
 4
 6
```
"""
struct Map{F} <: Transducer
    f::F
end

Map(::Type{T}) where T = Map{Type{T}}(T)  # specialization workaround

OutputSize(::Type{<:Map}) = SizeStable()
@inline next(rf::R_{Map}, result, input) = next(inner(rf), result, xform(rf).f(input))

#-----------------------------------------------------------------

# https://clojure.github.io/clojure/clojure.core-api.html#clojure.core/filter
# https://clojuredocs.org/clojure.core/filter
"""
    Filter(pred)

Skip items for which `pred` is evaluated to `false`.

$(_thx_clj("filter"))

# Examples
```jldoctest
julia> using Transducers

julia> 1:3 |> Filter(iseven) |> collect
1-element Vector{Int64}:
 2
```
"""
struct Filter{P} <: AbstractFilter
    pred::P
end

@inline next(rf::R_{Filter}, result, input) =
    xform(rf).pred(input) ? next(inner(rf), result, input) : result

#Adapt.adapt_structure(to, xf::Filter) = Filter(Adapt.adapt(to, xf.pred))

#-----------------------------------------------------------------

"""
    TerminateIf(pred)

Stop fold when `pred(x)` returns `true` for the output `x` of the
upstream transducer.

# Examples
```jldoctest
julia> 1:10 |> TerminateIf(x -> x == 3) |> fold((l,r) -> r)
3
```
"""
struct TerminateIf{P} <: AbstractFilter
    pred::P
end

function next(rf::R_{TerminateIf}, result0, input)
    shouldterminate = xform(rf).pred(input)
    result = next(inner(rf), result0, input)
    if shouldterminate
        return finished(result)
        #return finished(complete(inner(rf), result))
    end
    return result
end

#-----------------------------------------------------------------

# https://clojure.github.io/clojure/clojure.core-api.html#clojure.core/cat
# https://clojuredocs.org/clojure.core/cat
"""
    Cat()

Concatenate/flatten nested iterators.

$(_thx_clj("cat"))

# Examples
```jldoctest
julia> using Transducers

julia> collect(Cat(), [[1, 2], [3], [4, 5]]) == 1:5
true
```
"""
struct Cat <: Transducer
end

@inline function next(rf::R_{Cat}, acc, x)
    rf0, itr0 = retransform(inner(rf), asfoldable(x))
    return __fold__(rf0, acc, itr0, SequentialEx())
end
