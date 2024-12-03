

function Base.foreach(f, xf::Transducer, itr; executor=SequentialEx())
    fold(Returns(nothing), xf ⨟ Map(f), itr; init=nothing, executor) 
end

function Base.foreach(f, edu::Eduction; executor=SequentialEx())
    fold(Returns(nothing), edu |> Map(f); init=nothing, executor) 
end

# function Base.collect(xf::Transducer, itr; executor=SequentialEx())
#     xf_inner, itr_inner = extract_transducer(itr)
#     xf′ = xf_inner ⨟ xf 
#     _collect(xf′, OutputSize(xf′), itr, )
# end
