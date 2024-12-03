using TransducersNext
using Test
using ChunkSplitters

@testset "Transducer library" begin
    @testset "Map" begin
        @test fold(+, Map(sin), 1:10) ≈ sum(sin.(1:10))
    end

    @testset "Filter" begin
        @test fold(+, Filter(iseven), 1:10) ≈ sum(2:2:10)
    end

    @testset "TerminateIf" begin
        @test fold(+, TerminateIf(==(5)), 1:1000000) == sum(1:5)
    end
    
    @testset "Count" begin
        @test fold(+, Count(), zeros(10)) == sum(1:10)
    end
end

using Distributed
addprocs(2)
@everywhere using TransducersNext

@testset "Exectutors" begin
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
