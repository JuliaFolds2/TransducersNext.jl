const Comprehension = Union{
    Iterators.Generator,
    Iterators.Filter,
    Iterators.Flatten,
}

# Note, Transducers.jl stores an rf, which by defualt is Reduction(xform, Completing(push!!))
# I have no idea why this is done or what it really means. Probably it's the right way to do it,
# but I don't yet understand why.
struct Eduction{F <: Transducer, C} <: Foldable
    xf::F
    coll::C
end

Eduction(xform::Transducer, ed::Eduction) =
    Eduction(opcompose(Transducer(ed), xform), ed.coll)

Transducer(ed::Eduction) = ed.xf

"""
    eduction(iterator::Iterators.Generator)
    eduction(iterator::Iterators.Filter)
    eduction(iterator::Iterators.Flatten)

Convert an `iterator` to an eduction.  The iterators that are
typically used in the generator comprehensions are supported.

# Examples
```jldoctest
julia> using Transducers

julia> iter = (y for x in 1:10 if x % 2 == 0 for y in (x, x + 1));

julia> ed = eduction(iter);

julia> collect(iter) == collect(ed)
true
```
"""
eduction(itr::Comprehension) = eduction(extract_transducer(itr)...)
eduction(ed::Eduction) = ed
eduction(xform, coll) = Eduction(xform, coll)

"""
    Transducer(iterator::Iterators.Generator)
    Transducer(iterator::Iterators.Filter)
    Transducer(iterator::Iterators.Flatten)

Extract "processing" part of an `iterator` as a `Transducer`.  The
"data source" iterator (i.e., `xs` in `(f(x) for x in xs)`) is ignored
and `nothing` must be used as a place holder (i.e., `(f(x) for x in
nothing)`).

See also [`eduction`](@ref).

# Examples
```jldoctest
julia> using Transducers

julia> xf1 = Transducer(2x for x in nothing if x % 2 == 0);

julia> xf2 = opcompose(Filter(x -> x % 2 == 0), Map(x -> 2x));  # equivalent

julia> xs = 1:10
       collect(xf1, xs) == collect(xf2, xs)
true
```
"""
function Transducer(iter::Comprehension)
    xf, dataiter = extract_transducer(iter)
    dataiter === nothing && return xf

    if dataiter isa Iterators.ProductIterator
        throw(ArgumentError("""
              Conversion of the product generator comprehension, i.e.,
                  Transducer(... for x in xs, y in ys ...)
              is not supported.
              """))
    else
        throw(ArgumentError("""
              Unsupported iterator:
                  $(typeof(dataiter))
              Note that the "data source" iterator must be set to `nothing`.
              """))
    end
end

iterinner(iter::Iterators.Generator) = iter.iter
iterinner(iter::Iterators.Filter) = iter.itr
iterinner(iter::Iterators.Flatten) = iter.it
# iterf(iter::Iterators.Generate) = iter.f
# iterf(iter::Iterators.Filter) = iter.flt

function extract_transducer(ed::Eduction)
    xf, bottom = extract_transducer(ed.coll)
    return ed.xf ∘ xf, bottom
end

function extract_transducer(iter::Iterators.Generator)
    xf, bottom = extract_transducer(iterinner(iter))
    return Map(iter.f) ∘ xf, bottom
end

function extract_transducer(iter::Iterators.Filter)
    xf, bottom = extract_transducer(iterinner(iter))
    return Filter(iter.flt) ∘ xf, bottom
end

function extract_transducer(iter::Iterators.Flatten)
    xf, bottom = extract_transducer(iterinner(iter))
    return Cat() ∘ xf, bottom
end

"""
    Transducers.NoAdjoint(itr)

Bypass the optimization step by [`retransform`](@ref).
"""
struct NoAdjoint{T}
    itr::T
end

extract_transducer(itr::NoAdjoint) = IdentityTransducer(), itr.itr

# TODO: Consider doing the "opposite" of `extract_transducer` for
# `Partition` etc.:
# https://github.com/JuliaFolds/Transducers.jl/issues/7
"""
    extract_transducer(foldable) -> (xf, foldable′)

"Reverse" of [`eduction`](@ref).

# Examples
```jldoctest
julia> using Transducers

julia> double(x) = 2x;

julia> xs = 1:10;

julia> xf, foldable = Transducers.extract_transducer(Iterators.map(double, xs));

julia> xf == Map(double)
true

julia> foldable == xs
true
```
"""
extract_transducer(iter) = IdentityTransducer(), iter



"""
    Transducers.retransform(rf, itr) -> rf′, itr′

Extract transformations in `rf` and `itr` and use the appropriate adjoint for
better performance.

Note that the reducing function extracted from a comprehension such as `(f(x) for x ∈ itr)`
may not be `==` to `f` because of the way generator comprehensions work in Julia.
Use `Iterators.map` to specify an exact mapping function.

# Examples
```jldoctest
julia> using Transducers

julia> double(x) = 2x;

julia> itr0 = 1:10;

julia> itr1 = Iterators.map(double, itr0);

julia> rf, itr2 = Transducers.retransform(+, itr1);

julia> itr2 === itr0
true

julia> rf == reducingfunction(Map(double), +)
true
```
"""
function retransform(rf, itr1)
    xf, itr0 = extract_transducer(itr1)
    return reducingfunction(xf, rf), itr0
end

