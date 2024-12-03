"""
   asfoldable(x) -> foldable
   
By default, this function does nothing, but it can be overloaded to convert an input into another type before reducing over it.
This allows one to implement a foldable in terms of transducers over an existing type. For instance,

```julia
struct VectorOfVectors{T}
   v::Vector{Vector{T}}
end

Transducers.asfoldable(vov::VectorOfVectors{T}) = vov.v |> Cat()
```
Now we can do things like
```julia
julia> foldxl(+, VectorOfVectors([[1,2], [3, 4]]))
10
```
"""
asfoldable(x) = x

Base.IteratorSize(::Type{<:Reducible}) = Base.SizeUnknown()
