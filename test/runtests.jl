using Distributed
addprocs(2)
@everywhere using TransducersNext
using TransducersNext
using Test
using ChunkSplitters

@testset "basic smoketests" begin
    
    # Do some reduction
    f = sin
    op = (+)
    pred = iseven
    itr = 1:1000
    
    base_result = mapreduce(f, op, filter(pred, itr))
    
    for executor ∈ [SequentialEx(),
                    SIMDEx(),
                    ChunkedEx(;nchunks=2),
                    ChunkedEx(SequentialEx(); nchunks=3, split=RoundRobin()),
                    ThreadEx(),
                    ThreadEx(SequentialEx(); minsize=500),
                    ThreadEx(SIMDEx(); nchunks=500, minsize=500),
                    ThreadEx(SIMDEx(); nchunks=500, split=RoundRobin()),
                    DistributedEx(),
                    DistributedEx(ThreadEx(); nchunks=4),
                    ]
        # Test that the result from Base.mapreduce matches what Transducers produces
        @test base_result ≈ fold(op, Filter(pred) ⨟ Map(f), itr; executor)
        # Test the 'curried' version
        @test base_result ≈ (itr
                             |> Filter(pred)
                             |> Map(f)
                             |> fold(op; executor))

        # Lets try splitting up the data into a parition and then `Cat`-ing it
        par_itr = Iterators.partition(itr, 5)
        if executor isa SequentialEx
            # This version only works for SequentialEx since Iterators.parition has no methods for `chunks` / `index_chunks`
            @test base_result ≈ fold(op, par_itr |> Cat() |> Filter(pred) |> Map(f); executor)
        end
        # Same as above, but we `collect` the `parition` so we can try it on all the executors
        @test base_result ≈ fold(+, collect(par_itr) |> Cat() |> Filter(pred) |> Map(f); executor)
    end
end
