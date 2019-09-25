using CodeTracking
using JuliaInterpreter: getfile, locals
import ..Atom: fullpath, strlimit

function datatip(word, path, row, column, state::DebuggerState = STATE)
  # frame validation
  state.frame === nothing && return nothing

  frame = active_frame(state)
  scope = frame.framecode.scope

  # only work for methods
  scope isa Module && return nothing

  # path identity check
  path != fullpath(getfile(frame)) && return nothing

  # line number check
  defstr, startline = definition(String, scope)
  endline = startline + sum(c === '\n' for c in defstr)
  startline <= row <= endline || return nothing

  # local bindings
  for v in locals(frame)
    if string(v.name) == word
      valstr = @> repr(MIME("text/plain"), v.value, context = :limit => true) strlimit(1000)
      return [Dict(:type => :snippet, :value => valstr)]
    end
  end

  return nothing # when no local binding exists
end
