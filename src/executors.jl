
abstract type Executor end

struct SequentialEx <: Executor end
struct SIMDEx <: Executor end

struct ThreadEx{InnerEx <: Executor, NT <: NamedTuple} <: Executor
    inner_ex::InnerEx
    chunk_kwargs::NT
end
ThreadEx(; inner=SIMDEx(), kwargs...) = ThreadEx(inner, NamedTuple(kwargs))
