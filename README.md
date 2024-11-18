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
+ Multithreading is more performant and type inferrable
  + however, early termination is less mature than upstream
+ The implementation of `__foldl__` (now `__fold__`) is significantly simpler, and often more performant. We have a `foldstyle` trait for opting into certain classes of fold behaviour.
  + currently only `RecursiveFold` for `Tuple`/`NamedTuple`  and `RecursiveFold` for everything else. Traits might not be necessary here, I originally had a third trait for things which should use linear indexing but that's no longer needed, so perhaps this can just be a regular dispatch.
+ Don't yet support completion of stateful transducers
+ Don't yet have a `collect` / `tcollect` equivalent
+ Currently only supporting a very small subset of `Transducer`s from the original library (currently we have `Map`, `Filter`, `Cat`, and `TerminateIf`).

## Open design questions

see https://github.com/JuliaFolds2/TransducersNext.jl/issues?q=is%3Aissue+is%3Aopen+label%3A%22design+question%22
