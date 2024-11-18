function __fold__(rf::RF, init::T, itr, ex::ThreadEx) where {RF, T}
    tasks = map(chunks(itr; ex.chunk_kwargs...)) do chunk
        @spawn __fold__(rf, init, chunk, ex.inner_ex)
    end
    
    # # this is equivalent to
    # fold(Map(fetch), tasks) do ta, tb
    #     a = fetch(ta)
    #     @return_if_finished a
    #     b = fetch(tb)
    #     @return_if_finished b
    #     combine(rf, a, b)
    # end
    # but the above fold does not infer well, whereas the iterative peel does.
    let (task, rest) = Iterators.peel(tasks)
        result = fetch(task)
        @return_if_finished result
        for task in rest
            b = fetch(task)
            result = combine(rf, result, b)
            @return_if_finished result
        end
        result
    end
end
