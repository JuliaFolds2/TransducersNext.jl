@nospecialize

Base.show(io::IO, m::Map) = print(io, Map, "(", _repr(m.f), ")")
Base.show(io::IO, f::Filter) = print(io, Filter, "(", _repr(f.pred), ")")
Base.show(io::IO, f::TerminateIf) = print(io, TerminateIf, "(", _repr(f.pred), ")")
Base.show(io::IO, c::Cat) = print(io, Cat, "()")

function Base.show(io::IO, mime::MIME"text/plain", comp::Composition)
    show(io, mime, comp.outer)
    print(io, " ⨟\n  ")
    show(io, mime, comp.inner)
end

function Base.show(io::IO, comp::Composition)
    show(io, comp.outer)
    print(io, " ⨟ ")
    show(io, comp.inner)
end

is_anonymous(f) = startswith(string(f), '#')

_repr(f) = is_anonymous(f) ? repr(parentmodule(f)) * "." * String(nameof(f)) : repr(f)

function Base.show(io::IO, mime::MIME"text/plain", edu::Eduction)
    show(io, edu.coll)
    print(io, " |>\n  ")
    show(io, mime, edu.xf)
end
function Base.show(io::IO, edu::Eduction)
    show(io, edu.coll)
    print(io, " |> ")
    show(io, edu.xf)
end

@specialize
