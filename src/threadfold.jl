function __fold__(rf0::RF, init::T, itr, ex::ThreadEx) where {RF, T}
    (;nchunks, split, minsize) = ex
    if length(itr) <= minsize
        return __fold__(rf0, init, itr, ex.inner_ex)
    end    
    tasks = map(index_chunks(itr; n=ex.nchunks, split, minsize)) do inds
        @spawn  begin
            @inline getvalue(I) = @inbounds itr[I]
            rf = Map(getvalue)'(rf0)
            __fold__(rf, init, inds, ex.inner_ex)
        end
    end
    
    # # this is equivalent to
    # fold(tasks) do ta, tb
    #     a = @return_if_finished fetch(ta)
    #     b = @return_if_finished fetch(tb)
    #     combine(rf, a, b)
    # end
    # but the above fold does not infer well, whereas the iterative peel does.
    let (task, rest) = Iterators.peel(tasks)
        result = @return_if_finished fetch(task)
        for task in rest
            b = @return_if_finished fetch(task)
            result = combine(rf0, result, b)
        end
        result
    end
    # TODO: setup a wait-any style system that abandons the other tasks if one task
    # encounters a `Finished`. In this current setup, we might have `tasks[100]` finish early but end up needing to
    # wait for tasks[1] to finish.
end
