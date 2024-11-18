module TransducersNext

#=
The majority of the code in this repository is either straight up copied from Transducers.jl, or is a modified version
of functionality in Transducers.jl which is inspired by the ideas in that repository.

See https://github.com/JuliaFolds2/Transducers.jl

Once this package is ready, it will be turned into a PR to Transducers.jl, but for now it is starting from an empty git repo.
=#


using StableTasks: StableTasks, @spawn
using ConstructionBase: ConstructionBase
using CompositionsBase: CompositionsBase, ⨟, opcompose
using ChunkSplitters: ChunkSplitters, chunks

# using BangBang:
#     @!, BangBang, Empty, append!!, collector, empty!!, finish!, push!!, setindex!!, union!!

# using MicroCollections: MicroCollections, UndefVector, UndefArray


using InitialValues: InitialValue
using .Base.Broadcast: Broadcast, Broadcasted, instantiate

front(x) = Base.front(x)
tail(x) = Base.tail(x)

function transduce end
function fold end

function next end
function inner end
function xform end
function start end

export fold, Map, Filter, TerminateIf, Cat
export SequentialEx, SIMDEx, ThreadEx
export (⨟)


include("utils.jl")

@public __fold__, foldstyle, FoldStyle, IterateFold, RecursiveFold
@public Reduction, Transducer, Composition
@public reduction, reducingfunction
@public Finished, isfinished, finished, value, var"@return_if_finished"
@public next, var"@next", combine, inner, xform, start

include("core.jl")
include("library.jl")
include("eduction.jl")
include("executors.jl")
include("fold.jl")
include("threadfold.jl")




end # module TransducersNext
