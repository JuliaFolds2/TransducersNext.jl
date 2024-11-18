function fold(step::RF, xform::XF, itr; init=DefaultInit(), executor=SequentialEx()) where {RF, XF}
    rf0 = reducingfunction(xform, step)
    result = value(transduce(rf0, init, itr, executor))
    if result isa DefaultInit
        error(EmptyResultError(rf0))
    end
    result
end
fold(step, itr; kwargs...) = fold(step, IdentityTransducer(), itr; kwargs...)
fold(step; kwargs...) = itr -> fold(step, itr; kwargs...)

function transduce(rf1::RF, init, coll, ex) where {RF <: AbstractReduction}
    rf0, foldable = retransform(rf1, asfoldable(coll))
    state = start(rf0, init)
    __fold__(rf0, state, foldable, ex)
end

abstract type FoldStyle end
struct IterateFold <: FoldStyle end
struct RecursiveFold <: FoldStyle end

foldstyle(itr) = IterateFold()
foldstyle(::Union{Tuple, NamedTuple}) = RecursiveFold()

function __fold__(rf::RF, init::T, itr, ex) where {RF, T}
    __fold__(foldstyle(itr), rf, init, itr, ex)
end

function __fold__(::IterateFold, rf::RF, init::T, itr, ::SequentialEx) where {RF, T}
    val = init
    @unroll 8 for x in itr
        val = @next(rf, val, x)
    end
    return val
end

function __fold__(::IterateFold, rf0::RF, init::T, itr, ::SIMDEx) where {RF, T}
    val = init
    @inline getvalue(I) = @inbounds itr[I]
    rf = Map(getvalue)'(rf0)
    @unroll_simd 8 for i in eachindex(itr)
        val = @next(rf, val, i)
    end
    return val
end


function __fold__(::RecursiveFold, rf::RF, val::T, itr::Itr, ex::Union{SequentialEx, SIMDEx}) where {RF, T, Itr}
    if isempty(itr)
        val
    else
        x, rest = front(itr), tail(itr)
        val′ = @next(rf, val, x)
        __fold__(foldstyle(rest), rf, val′, rest, ex)
    end
end

#----------------------------------------------------------------
# Error stuff
struct EmptyResultError <: Exception
    rf
end

function Base.showerror(io::IO, e::EmptyResultError)
    println(
        io,
        "EmptyResultError: ",
        "Reducing function `", _realbottomrf(e.rf), "` is never called. ")
    print(
        io,
        "The input collection is empty or the items are all filtered out ",
        "by some transducer(s). ",
        "It is recommended to specify `init` to avoid this error.")
    # TODO: improve error message
end
    
_realbottomrf(op) = op
_realbottomrf(rf::AbstractReduction) = _realbottomrf(as(rf, BottomRF).inner)
# _realbottomrf(rf::Completing) = rf.f

check_empty(rf, result) = value(result) isa DefaultInit ? throw(EmptyResultError(rf)) : result

