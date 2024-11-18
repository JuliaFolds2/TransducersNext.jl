# TransducersNext.jl

This package is a staging ground for a major rewrite/overhaul of [Transducers.jl](https://github.com/JuliaFolds2/Transducers.jl). The focus currently is on only moving code here that is actually understood (Transducers.jl has a lot of complex code that none of the maintainers actually understand).

Once this package is ready, it will be turned into a PR to Transducers.jl, but for now it is starting from an empty git repo. Most of the code here is tweaked or straight up copied from Transducers.jl.

Please see https://www.youtube.com/watch?v=OFw1Cu220eA for a simple overview of what transducers are, the current state of the Transducers ecosystem, and what we'd like to see happen in the near future with Transducers.jl

``` julia
julia> fold(+, Filter(iseven) ⨟ Map(sin), 1:1000; executor=ThreadEx(n=8))
0.5539363521120523

julia> 1:1000 |> Filter(iseven) |> Map(sin) |> fold(+; executor=ThreadEx(n=8))
0.5539363521120523
```

## Major changes in TransducersNext.jl relative to Transducers.jl

+ `foldxl`, `foldxt`, `foldxd`, etc. have been replaced with `fold`. Choosing threads, SIMD, or other backends (no other ones yet supported) is done with an `executor` argument, e.g. `fold(+, Map(sin), v; executor=ThreadsEx(;n=8))`
  + Executors support nesting. For example, `ThreadsEx` holds an inner executor. The idea here is that you might want to say "first split up the reduction across distributed processes, then split those sub-reductions up onto different threads on those processes, and then do SIMD reductions for the sub-sub-reductions"
+ Multithreading is more performant and type inferrable
  + however, early termination is less mature than upstream
+ The implementation of `__foldl__` (now `__fold__`) is significantly simpler, and often more performant. We have a `foldstyle` trait for opting into certain classes of fold behaviour.
  + currently only `RecursiveFold` for `Tuple`/`NamedTuple`  and `IterateFold` for everything else. Traits might not be necessary here, I originally had a third trait for things which should use linear indexing but that's no longer needed, so perhaps this can just be a regular dispatch.
+ Don't yet support completion of stateful transducers
+ Don't yet have a `collect` / `tcollect` equivalent
+ Currently only supporting a very small subset of `Transducer`s from the original library (currently we have `Map`, `Filter`, `Cat`, and `TerminateIf**).
+ Iterating an `Eduction` is currently not supported.

## Open design questions

see https://github.com/JuliaFolds2/TransducersNext.jl/issues?q=is%3Aissue+is%3Aopen+label%3A%22design+question%22

Please open new issues if you have design questions or ideas of your own.

## What is a Transducer?

A `Transducer` is a protocol for *trans*forming a re*duc*ing function. `fold(+, Filter(iseven) ⨟ Map(sin), v)` essentially 
says "add up all the elements of `v`, but before adding them, we discard the non-even numbers and we apply the `sin`
function to each element.

Rather than using the (iteration protocol)[https://docs.julialang.org/en/v1/manual/interfaces/#man-interface-iteration] 
to transform `v` into an iterator of even numbers where `sin` has been applied, Transducers work by transforming `+` 
into a new reducing operator, `rf = (Filter(iseven) ⨟ Map(sin))'(+)` which is equivalent to 
`rf = (x, y) -> iseven(y) ? x + sin(y) : x`. Thus, writing `fold(+, Filter(iseven) ⨟ Map(sin), v)` generates code 
equivalent to

``` julia
acc = init
for x in v
    if iseven(x)
        acc = acc + sin(x)
    else
        acc = acc
    end
end
```
which is more efficient than an equivalent `Iterator` based approach. 

The fundamental idea behind this design is to disentangle 'what you want to do' from 'how you do it' and 'what 
type of container your data came from'.

TransducersNext.jl in particular would start with 

``` julia
fold(+, Filter(iseven) ⨟ Map(sin), v)
```
and then call

``` julia
# inside `fold`
rf = (Filter(iseven) ⨟ Map(sin))'(+)
init = DefaultInit() # can be set as a kwarg
exec = SequentialEx()  # can be set as a kwarg
state = start(rf, init) # this initializes any setup that might need to be done for `rf` before the loop

result = __fold__(rf, state, v, exec) # the main workhorse

if result isa DefaultInit
    error(EmptyResultError(rf0)) # tell the user that they reduced over an empty collection
end
result
```
the call to `__fold__` will become

``` julia
# inside `fold`
## inside __fold__
@unroll 8 for x in v
    state = @next(rf, state, x)
end
state
```
where `@unroll 8` says "manually peel out the first 8 iterations" (this is here to help with type stability), and `@next` is a shortcut for writing

``` julia
# inside `fold`
## inside __fold__
### inside @next
val = next(rf, state, x) # next usually just does `rf(state, x)`
if val isa Finished # this is for early termination
    return val # break out of the `for` loop
else
    val
end
```
