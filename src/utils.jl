_cljapiurl(name) =
    "https://clojure.github.io/clojure/clojure.core-api.html#clojure.core/$name"
_cljref(name) =
    "[`$name` in Clojure]($(_cljapiurl(name)))"
_thx_clj(name) =
    "This API is modeled after $(_cljref(name))."


struct Finished{T}
    value::T
end

value(x) = x
value(x::Finished) = x.value
finished(x::Finished) = x
finished(x) = Finished(x)
finished() = Finished(nothing)
isfinished(x) = x isa Finished

macro return_if_finished(ex)
    quote
        val = $(esc(ex))
        val isa Finished && return val
        val
    end
    # Base.replace_linenums!(ex, __source__)
end

macro next(rf, state, input)
    quote
        result = next($(esc.((rf, state, input))...))
        @return_if_finished(result)
    end
end

macro unroll(N::Int, loop)
    unroll_macro(N, loop; simd=false)
end

macro unroll_simd(N::Int, loop)
    unroll_macro(N, loop; simd=true)
end

function unroll_macro(N, loop; simd)
    loop_info = if simd == true 
        Expr(:loopinfo, Symbol("julia.simdloop"), nothing)
    elseif simd == false
        nothing
    elseif simd == :ivdep
        Expr(:loopinfo, Symbol("julia.simdloop"), nothing)
    else
        
    end
    Base.isexpr(loop, :for) || error("only works on for loops")
    Base.isexpr(loop.args[1], :(=)) || error("This loop pattern isn't supported")
    val, itr = esc.(loop.args[1].args)
    body = esc(loop.args[2])
    out = Expr(:block, :(itr = $itr), :(next = iterate(itr)))
    unrolled = map(1:N) do _
        quote
            $val, state = next
            $body
            next = iterate(itr, state)
        end
    end
    remainder = quote
        while true
            $val, state = next
            $body
            next = iterate(itr, state)
            next !== nothing || break
            $loop_info
        end
    end
    if_nest = foldr(unrolled; init=remainder) do prev, next
        quote
            $prev
            if next !== nothing
                $next
            end
        end
    end
    push!(out.args, :(if next !== nothing; $if_nest end))
    out
end


macro public(ex)
    if VERSION >= v"1.11.0-DEV.469"
        args = ex isa Symbol ? (ex,) : Base.isexpr(ex, :tuple) ? ex.args :
            error("malformed input to `@public`: $ex")
        esc(Expr(:public, args...))
    else
        nothing
    end
end

