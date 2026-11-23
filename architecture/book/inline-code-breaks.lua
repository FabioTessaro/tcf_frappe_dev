-- Pandoc Lua filter (PDF only): let long inline code such as paths and dotted
-- method names break across lines after / . _ - = , : so they stay inside the margin.

local escapes = {
  ["\\"] = "\\textbackslash{}", ["{"] = "\\{", ["}"] = "\\}", ["$"] = "\\$",
  ["&"] = "\\&", ["#"] = "\\#", ["%"] = "\\%", ["_"] = "\\_",
  ["^"] = "\\textasciicircum{}", ["~"] = "\\textasciitilde{}",
}
local breakable = { ["/"] = true, ["."] = true, ["_"] = true, ["-"] = true,
                    ["="] = true, [","] = true, [":"] = true }

function Code(el)
  if not FORMAT:match("latex") or utf8.len(el.text) < 16 then
    return nil
  end
  local out = {}
  for _, cp in utf8.codes(el.text) do
    local ch = utf8.char(cp)
    out[#out + 1] = escapes[ch] or ch
    if breakable[ch] then
      out[#out + 1] = "\\allowbreak{}"
    end
  end
  return pandoc.RawInline("latex", "\\texttt{" .. table.concat(out) .. "}")
end
