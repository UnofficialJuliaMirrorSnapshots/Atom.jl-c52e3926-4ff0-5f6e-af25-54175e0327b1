#=
Find toplevel items (bind / call)

- downstreams: modules.jl, outline.jl, goto.jl
=#


abstract type ToplevelItem end

struct ToplevelBinding <: ToplevelItem
    expr::CSTParser.EXPR
    bind::CSTParser.Binding
    lines::UnitRange{Int}
end

struct ToplevelCall <: ToplevelItem
    expr::CSTParser.EXPR
    lines::UnitRange{Int}
    callstr::String
end

struct ToplevelTupleH <: ToplevelItem
    expr::CSTParser.EXPR
    lines::UnitRange{Int}
end

"""
    toplevelitems(text; kwargs...)::Vector{ToplevelItem}

Finds and returns toplevel "item"s (call and binding) in `text`.

keyword arguments:
- `mod::Union{Nothing, String}`: if not `nothing` don't return items within modules
    other than `mod`, otherwise enter into every module.
- `inmod::Bool`: if `true`, don't include toplevel items until it enters into `mod`.
"""
function toplevelitems(text; kwargs...)
    parsed = CSTParser.parse(text, true)
    _toplevelitems(text, parsed; kwargs...)
end

function _toplevelitems(
    text, expr,
    items::Vector{ToplevelItem} = Vector{ToplevelItem}(), line = 1, pos = 1;
    mod::Union{Nothing, String} = nothing,
    inmod::Bool = false,
)
    # add items if `mod` isn't specified or in a target modle
    if mod === nothing || inmod
        # binding
        bind = CSTParser.bindingof(expr)
        if bind !== nothing
            lines = line:line+countlines(expr, text, pos, false)
            push!(items, ToplevelBinding(expr, bind, lines))
        end

        lines = line:line+countlines(expr, text, pos, false)

        # toplevel call
        if iscallexpr(expr)
            push!(items, ToplevelCall(expr, lines, str_value_as_is(expr, text, pos)))
        end

        # destructure multiple returns
        if ismultiplereturn(expr)
            push!(items, ToplevelTupleH(expr, lines))
        end
    end

    # look for more toplevel items in expr:
    if shouldenter(expr, mod)
        if expr.args !== nothing
            if ismodule(expr) && shouldentermodule(expr, mod)
                inmod = true
            end
            for arg in expr.args
                _toplevelitems(text, arg, items, line, pos; mod = mod, inmod = inmod)
                line += countlines(arg, text, pos)
                pos += arg.fullspan
            end
        end
    end
    return items
end

function shouldenter(expr::CSTParser.EXPR, mod::Union{Nothing, String})
    !(scopeof(expr) !== nothing && !(
        expr.typ === CSTParser.FileH ||
        (ismodule(expr) && shouldentermodule(expr, mod)) ||
        isdoc(expr)
    ))
end

shouldentermodule(expr::CSTParser.EXPR, mod::Nothing) = true
shouldentermodule(expr::CSTParser.EXPR, mod::String) = expr.binding.name == mod
