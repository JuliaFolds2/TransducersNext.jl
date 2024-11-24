
abstract type Executor end

"""
    SequentialEx <: Executor

    SequentialEx()

The default sequential executor for `fold`s. This executor semantically guarentees that items from the input collection
are processed in-order sequentially.

### Examples

```julia
julia> fold(+, Map(x -> 2x), 1:10; executor=SequentialEx())
110
```
"""
struct SequentialEx <: Executor end

"""
    SIMDEx <: Executor

    SIMDEx()

This executor tells Transducers to attempt to vectorize the reduction (this is done by sending the LoopInfo
`julia.simdloop` to LLVM). Using this executor typically requires that your input collection is indexable.
SIMD reductions are only equivalent to sequential reductions if the reducing operator is at least
approximately [associative](https://en.wikipedia.org/wiki/Associative_property). This means that the `op` in
`fold(op, xf, coll)` should have the property that `op(a, op(b, c)) ≈ op(op(a, b), c)`.

### Examples

```
julia> fold(+, Map(x -> 2x), 1:10; executor=SIMDEx())
110
```
"""
struct SIMDEx <: Executor end



Base.@kwdef struct ChunkedEx{InnerEx <: Executor, NC, SP} <: Executor
    inner_ex::InnerEx = SIMDEx()
    nchunks::NC
    split::SP = Consecutive()
    minsize::Int = 1
end
ChunkedEx(inner_ex; kwargs...) = ChunkedEx(;inner_ex, kwargs...)


"""
    ThreadEx <: Executor

    ThreadEx(; inner_ex=SIMDEx(), nchunks=nthreads(), split=Consecutive(), minsize=1)

This executor uses [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) to split collections into sub-collections
and then distribute those sub-collections amongs `nchunks` tasks (defaults to the total number of threads julia was started with).
This typically requires that the collection is indexable. See ChunkSplitters.jl for more details (the `nchunks` kwarg here
corresponds to the `n` kwarg in ChunkSplitters.jl).

The `split` kwarg determines how the sub-collections are made, the default is `Consecutive()`, but `RoundRobin()` is also supported.
Note that while `Consecutive()` splits are parallelizable with an associative reducing operator, `RoundRobin()` splits require not
only associativity, but commutivity as well. See ChunkSplitters.jl for more details.

The `minsize` keyword argument controls the lower-bound on a chunk's size. That means that e.g. if you did a reduction over a
collection of `10` elements, but set `minsize=100`, the reduction would not be multithreaded. See ChunkSplitters.jl for more
details.

The `inner_ex` keyword argument (default `SIMDEx()`) controls the executor used for the inner reduction performed on the
sub-collections. This can be used to e.g. have nested multithreading, control whether or not you want `SIMD` performed on your
inner loops, or perhaps in the future, have each thread spawn separate sub-reductions on separate GPUs once we have e.g.
a `GPUEx()`.

### Examples

```
julia> using TransducersNext

julia> fold(+, Map(x -> (@show(Threads.threadid()); 2x)), 1:6; executor=ThreadEx())
Threads.threadid() = 6
Threads.threadid() = 4
Threads.threadid() = 5
Threads.threadid() = 2
Threads.threadid() = 3
Threads.threadid() = 1
42

julia> fold(+, Map(x -> (@show(Threads.threadid()); 2x)), 1:6; executor=ThreadEx(;nchunks=2))
Threads.threadid() = 1
Threads.threadid() = 6
Threads.threadid() = 6
Threads.threadid() = 6
Threads.threadid() = 1
Threads.threadid() = 1
42
```

"""
Base.@kwdef struct ThreadEx{InnerEx <: Executor, NC, SP} <: Executor
    inner_ex::InnerEx = SIMDEx()
    nchunks::NC = Threads.nthreads()
    split::SP = Consecutive()
    minsize::Int = 1
end
ThreadEx(inner_ex; kwargs...) = ThreadEx(;inner_ex, kwargs...)


"""
    DistributedEx <: Executor

    DistributedEx(; inner_ex=SIMDEx(), nchunks=nthreads(), split=Consecutive(), minsize=1)

using this executor requires Distributed.jl to be loaded, and TransducersNext to be loaded on each sub-process. 

This executor uses [ChunkSplitters.jl](https://github.com/JuliaFolds2/ChunkSplitters.jl) to split collections into sub-collections
and then distribute those sub-collections amongs `nchunks` sub-processes. This typically requires that the collection is indexable.
See ChunkSplitters.jl for more details (the `nchunks` kwarg here corresponds to the `n` kwarg in ChunkSplitters.jl).

The `split` kwarg determines how the sub-collections are made, the default is `Consecutive()`, but `RoundRobin()` is also supported.
Note that while `Consecutive()` splits are parallelizable with an associative reducing operator, `RoundRobin()` splits require not
only associativity, but commutivity as well. See ChunkSplitters.jl for more details. An
[associative operator](https://en.wikipedia.org/wiki/Associative_property) is one for which `op(a, op(b, c)) == op(op(a, b), c)`
whereas a commutative operator is one for which `op(a, b) == op(b, a)`.

The `minsize` keyword argument controls the lower-bound on a chunk's size. That means that e.g. if you did a reduction over a
collection of `10` elements, but set `minsize=100`, the reduction would not be parallelized. See ChunkSplitters.jl for more
details.

The `inner_ex` keyword argument (default `SIMDEx()`) controls the executor used for the inner reduction performed on the
sub-collections. This is very useful for multi-node setups where you have one distributed process per node, but then want to
mulithread within that node, e.g. `DistributedEx(inner_ex=ThreadEx())`.

### Examples
```
julia> using Distributed; addprocs(4);

julia> @everywhere using TransducersNext

julia> xf = Map() do x
           @show Threads.threadid()
           2x
       end;

julia> fold(+, xf, 1:6; executor=DistributedEx())
      From worker 5:    Threads.threadid() = 1
      From worker 2:    Threads.threadid() = 1
      From worker 3:    Threads.threadid() = 1
      From worker 3:    Threads.threadid() = 1
      From worker 3:    Threads.threadid() = 1
      From worker 4:    Threads.threadid() = 1
42

julia> fold(+, xf, 1:12; executor=DistributedEx(inner_ex=ThreadEx()))
      From worker 4:    Threads.threadid() = 5
      From worker 4:    Threads.threadid() = 4
      From worker 4:    Threads.threadid() = 7
      From worker 4:    Threads.threadid() = 6
      From worker 4:    Threads.threadid() = 2
      From worker 2:    Threads.threadid() = 1
      From worker 2:    Threads.threadid() = 3
      From worker 5:    Threads.threadid() = 2
      From worker 5:    Threads.threadid() = 1
      From worker 5:    Threads.threadid() = 4
      From worker 3:    Threads.threadid() = 1
      From worker 3:    Threads.threadid() = 2
156
```
"""
Base.@kwdef struct DistributedEx{InnerEx <: Executor, NC, SP} <: Executor
    inner_ex::InnerEx = SIMDEx()
    nchunks::NC = get_nprocs()
    split::SP = Consecutive()
    minsize::Int = 1
end
DistributedEx(inner_ex; kwargs...) = DistributedEx(;inner_ex, kwargs...)

# this is a function stub that will get a method added to it when Distributed.jl is loaded
function get_nprocs end


struct TurboEx <: Executor end
