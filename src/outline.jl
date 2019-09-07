using CSTParser

handle("outline") do text
    return outline(text)
end

function outline(text)
    parsed = CSTParser.parse(text, true)
    toplevel_bindings(parsed, text)
end

# need to keep this consistent with wstype
static_type(bind::CSTParser.Binding) = static_type(bind.val)
function static_type(val::CSTParser.EXPR)
    if CSTParser.defines_function(val)
        "function"
    elseif CSTParser.defines_macro(val)
        "snippet"
    elseif CSTParser.defines_module(val)
        "module"
    elseif CSTParser.defines_struct(val) ||
           CSTParser.defines_abstract(val) ||
           CSTParser.defines_mutable(val) ||
           CSTParser.defines_primitive(val)
        "type"
    else
        "variable"
    end
end

# need to keep this consistent with wsicon
static_icon(bind::CSTParser.Binding) = static_icon(bind.val)
function static_icon(val::CSTParser.EXPR)
    if CSTParser.defines_function(val)
        "λ"
    elseif CSTParser.defines_macro(val)
        "icon-mention"
    elseif CSTParser.defines_module(val)
        "icon-package"
    elseif CSTParser.defines_struct(val) ||
           CSTParser.defines_abstract(val) ||
           CSTParser.defines_mutable(val) ||
           CSTParser.defines_primitive(val)
        "T"
    else
        "v"
    end
end

function toplevel_bindings(expr, text, bindings = [], line = 1, pos = 1)
    bind = CSTParser.bindingof(expr)
    if bind !== nothing
        name = bind.name
        if CSTParser.has_sig(bind.val)
            sig = CSTParser.get_sig(bind.val)
            name = str_value(sig)
        end
        push!(bindings, Dict(
                :name => name,
                :type => static_type(bind),
                :icon => static_icon(bind),
                :lines => [line, line + count(c -> c === '\n', text[nextind(text, pos - 1):prevind(text, pos + expr.span)])]
                )
             )
    end
    scope = CSTParser.scopeof(expr)
    if scope !== nothing && !(expr.typ === CSTParser.FileH || expr.typ === CSTParser.ModuleH || expr.typ === CSTParser.BareModule)
        return bindings
    end
    if expr.args !== nothing
        for arg in expr.args
            toplevel_bindings(arg, text, bindings, line, pos)
            line += count(c -> c === '\n', text[nextind(text, pos - 1):prevind(text, pos + arg.fullspan)])
            pos += arg.fullspan
        end
    end
    return bindings
end

struct LocalScope
    name
    span
    children
    expr
end

struct LocalBinding
    name
    span
    expr
end

function local_bindings(expr, bindings = [], pos = 1)
    bind = CSTParser.bindingof(expr)
    scope = CSTParser.scopeof(expr)
    if bind !== nothing && scope === nothing
        push!(bindings, LocalBinding(bind.name, pos:pos+expr.span, expr))
    end
    if scope !== nothing
        range = pos:pos+expr.span
        localbindings = []
        if expr.args !== nothing
            for arg in expr.args
                local_bindings(arg, localbindings, pos)

                pos += arg.fullspan
            end
        end
        push!(bindings, LocalScope(bind === nothing ? "" : bind.name, range, localbindings, expr))
        return bindings
    elseif expr.args !== nothing
        for arg in expr.args
            local_bindings(arg, bindings, pos)
            pos += arg.fullspan
        end
    end
    return bindings

end

function locals(text, line, col)
    byteoffset = 1
    current_line = 1
    current_char = 0
    for c in text
        if line == current_line
            current_char += 1
            c === '\n' && break
        end
        current_char == col && break
        byteoffset += VERSION >= v"1.1" ? ncodeunits(c) : ncodeunits(string(c))
        c === '\n' && (current_line += 1)
    end
    parsed = CSTParser.parse(text, true)

    bindings = local_bindings(parsed)
    bindings = filter_local_bindings(bindings, byteoffset)
    bindings = filter(x -> !isempty(x[:name]), bindings)
    bindings = sort(bindings, lt = (a,b) -> a[:locality] < b[:locality])
    bindings = unique(x -> x[:name], bindings)

    bindings
end

function filter_local_bindings(bindings, byteoffset, root = "", actual_bindings = [])
    for bind in bindings
        push!(actual_bindings, Dict(
            :name => bind.name,
            :root => root,
            :locality => abs(bind.span[1] - byteoffset),
            :icon => static_icon(bind.expr),
            :type => static_type(bind.expr)
        ))
        if bind isa LocalScope && byteoffset in bind.span
            filter_local_bindings(bind.children, byteoffset, bind.name, actual_bindings)
        end
    end
    actual_bindings
end

# https://github.com/julia-vscode/DocumentFormat.jl/blob/b7e22ca47254007b5e7dd3c678ba27d8744d1b1f/src/passes.jl#L108
function str_value(x)
    if x.typ === CSTParser.PUNCTUATION
        x.kind == CSTParser.Tokens.LPAREN && return "("
        x.kind == CSTParser.Tokens.LBRACE && return "{"
        x.kind == CSTParser.Tokens.LSQUARE && return "["
        x.kind == CSTParser.Tokens.RPAREN && return ")"
        x.kind == CSTParser.Tokens.RBRACE && return "}"
        x.kind == CSTParser.Tokens.RSQUARE && return "]"
        x.kind == CSTParser.Tokens.COMMA && return ","
        x.kind == CSTParser.Tokens.SEMICOLON && return ";"
        x.kind == CSTParser.Tokens.AT_SIGN && return "@"
        x.kind == CSTParser.Tokens.DOT && return "."
        return ""
    elseif x.typ === CSTParser.IDENTIFIER || x.typ === CSTParser.LITERAL || x.typ === CSTParser.OPERATOR || x.typ === CSTParser.KEYWORD
        return CSTParser.str_value(x)
    else
        s = ""
        for a in x
            s *= str_value(a)
        end
        return s
    end
end
