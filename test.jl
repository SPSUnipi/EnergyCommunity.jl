function test(; kwargs...)
    print(kwargs)

    return kwargs
end

kwargs = test(c=5, y=6)