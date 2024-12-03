privatestate(::T, state, result) where {T <: AbstractReduction} =
    privatestate(T, state, result)


complete(rf::BottomRF, result) = complete(inner(rf), result)
combine(rf::BottomRF, a, b) = combine(inner(rf), a, b)

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
# start(rf::R_{AbstractFilter}, result) = start(inner(rf), result) # Why did this method exist?

"""
    complete(rf::R_{X}, state)

This is an optional interface for a transducer.  If transducer `X` has
some internal state, this is the last chance to "flush" the result.

See [`PartitionBy`](@ref), etc. for real-world examples.

If `start(rf::R_{X}, state)` is defined, `complete` **must** unwarp
`state` before returning `state` to the outer reducing function.
"""
complete(f, result) = next(f, DefaultInit(), result) # This used to be f(result), I'm gonna try this though.
function complete(rf::AbstractReduction, result)
    # Not using dispatch to avoid ambiguity
    if ownsstate(rf, result)
        complete_stateful_error(rf)
    else
        complete(inner(rf), result)
    end
end
@noinline function complete_stateful_error(rf)
    error("`complete` for ", typeof(xform(rf)), " is not defined, ",
          "it is mandatory for reductions with private state to implement ",
          "a `complete` method.")
end 

@inline psstate(ps) = ps.state
@inline psresult(ps) = ps.result
@inline setpsstate(ps, x) = @set ps.state = x
@inline setpsresult(ps, x) = @set ps.result = x

ownsstate(::Any, ::Any) = false
ownsstate(::R, ::PrivateState{T}) where {R, T} = R === T
# Using `result isa PrivateState{typeof(rf)}` makes it impossible to
# compile Extrema examples in ../examples/tutorial_missings.jl (it
# took more than 10 min).  See also:
# https://github.com/JuliaLang/julia/issues/30125

"""
    unwrap(rf, result)

Unwrap [`wrap`](@ref)ed `result` to a private state and inner result.
Following identity holds:

```julia
unwrap(rf, wrap(rf, state, iresult)) == (state, iresult)
```

This is intended to be used only in [`complete`](@ref).  Inside
[`next`](@ref), use [`wrapping`](@ref).
"""
unwrap(::T, ps::PrivateState{T}) where {T} = (psstate(ps), psresult(ps))

unwrap(::T1, ::PrivateState{T2}) where {T1, T2} =
    error("""
    `unwrap(rf1, ps)` is used for
    typeof(rf1) = $T1
    while `ps` is created by wrap(rf2, ...) where
    typeof(rf2) = $T2
    """)




"""
    wrap(rf::R_{X}, state, iresult)

Pack private `state` for reducing function `rf` (or rather the
transducer `X`) with the result `iresult` returned from the inner
reducing function `inner(rf)`.  This packed result is typically passed
to the outer reducing function.

This is intended to be used only in [`start`](@ref).  Inside
[`next`](@ref), use [`wrapping`](@ref).

!!! note "Implementation detail"

    If `iresult` is a [`Finished`](@ref), `wrap` actually _un_wraps all
    internal state `iresult` recursively.  However, this is an
    implementation detail that should not matter when writing
    transducers.

Consider a reducing step constructed as

    rf = opcompose(xf₁, xf₂, xf₃)'(f)

where each `xfₙ` is a stateful transducer and hence needs a private
state `stateₙ` and this `stateₙ` is constructed in each
`start(::R_{typeof(xfₙ)}, result)`.  Then, calling `start(rf,
result))` is equivalent to

```julia
wrap(rf,
     state₁,                     # private state for xf₁
     wrap(inner(rf),
          state₂,                # private state for xf₂
          wrap(inner(inner(rf)),
               state₃,           # private state for xf₃
               result)))
```

or equivalently

```julia
result₃ = result
result₂ = wrap(inner(inner(rf)), state₃, result₃)
result₁ = wrap(inner(rf),        state₂, result₂)
result₀ = wrap(rf,               state₁, result₁)
```

The inner most step function receives the original `result` as the
first argument while transducible processes such as [`foldl`](@ref)
only sees the outer-most "tree" `result₀` during the reduction.

See [`wrapping`](@ref), [`unwrap`](@ref), and [`start`](@ref).
"""
wrap(rf::T, state, iresult) where {T} = privatestate(rf, state, iresult)
wrap(rf, state, iresult::Finished) = iresult

"""
    wrapping(f, rf, result)

Function `f` must take two argument `state` and `iresult`, and return
a tuple `(state, iresult)`.  This is intended to be used only in
[`next`](@ref), possibly with a `do` block.

```julia
next(rf::R_{MyTransducer}, result, input) =
    wrapping(rf, result) do my_state, iresult
        # code calling `next(inner(rf), iresult, possibly_modified_input)`
        return my_state, iresult  # possibly modified
    end
```

See [`wrap`](@ref), [`unwrap`](@ref), and [`next`](@ref).
"""
@inline function wrapping(f, rf, result)
    #=
    state0, iresult0 = unwrap(rf, result)
    state1, iresult1 = f(state0, iresult0)
    =#
    # `first`/`last` behaves nicer with type inference for `Union` of `Tuple`s:
    a = unwrap(rf, result)
    state0 = first(a)
    iresult0 = last(a)
    b = f(state0, iresult0)
    state1 = first(b)
    iresult1 = last(b)
    return wrap(rf, state1, iresult1)
end

unwrap_all(ps::PrivateState) = unwrap_all(psresult(ps))
unwrap_all(result) = result
unwrap_all(ps::Finished) = Finished(unwrap_all(unreduced(ps)))


# """
#     Transducers.completebasecase(rf, state)

# Process basecase result `state` before merged by [`combine`](@ref).

# For example, on GPU, this function can be used to translate mutable states to
# immutable values for exchanging them through (un-GC-managed) memory.  See
# [`whencompletebasecase`](@ref).

# !!! note

#     This function is an internal experimental interface for FoldsCUDA.
# """
# completebasecase(_, result) = result
# completebasecase(rf::RF, result) where {RF <: AbstractReduction} =
#     completebasecase(inner(rf), result)
# @inline completebasecase(rf::BottomRF, result) = completebasecase(inner(rf), result)
