local defaults = require'vroom.defaults'
local perm = require'vroom.perm'

local M = {}

-- Word regex.
--
-- Used to tag words with hints.
M.by_word_start = vim.regex('\\<\\w\\+')

-- Turn a table representing a hint into a string.
local function tbl_to_str(hint)
  local s = ''

  for i = 1, #hint do
    s = s .. hint[i]
  end

  return s
end

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
end

-- Mark the current line with hints whenever the input regex matches.
--
-- This function applies reg repeatedly until it fails (typically at the end of
-- the line). For every match of the regex, a hint placeholder is generated, which
-- contains two fields giving the line and column of the hint:
--
--   { line, col }
--
-- The input line_nr is the line number of the line currently being marked.
function M.mark_hints_line(reg, line_nr, line)
  local hints = {}

  local col = 1
  while true do
    local s = line:sub(col)
    local b, e = reg:match_str(s)

    if b == nil then
      break
    end

    hints[#hints + 1] = { line = line_nr; col = vim.str_utfindex(line, col + b) }

    col = col + e
  end

  return hints
end

-- Reduce a hint.
--
-- This function will remove hints not starting with the input key and will reduce the other ones
-- with one level.
function M.reduce_hint(hint, key)
  if hint:sub(1, 1) == key then
    hint = hint:sub(2)
  end

  if hint == '' then
    hint = nil
  end

  return hint
end

-- Reduce all hints and return the one fully reduced, if any.
function M.reduce_hints_lines(per_line_hints, key)
  local output = {}
  local update_count = 0

  for _, hints in pairs(per_line_hints) do
    local next_hints = {}

    for _, h in pairs(hints) do
      local prev_hint = h.hint
      h.hint = M.reduce_hint(h.hint, key)

      if h.hint == nil then
        return h
      elseif h.hint ~= prev_hint then
        next_hints[#next_hints + 1] = h
        update_count = update_count + 1
      end
    end

    output[#output + 1] = next_hints
  end

  return nil, output, update_count
end

function M.create_hints(reg, buf_height, cursor_pos, lines, opts)
  local keys = opts and opts.keys or defaults.keys
  local reverse_distribution = opts and opts.reverse_distribution or defaults.reverse_distribution

  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}
  local indirect_hints = {}
  for i = 1, buf_height do
    local line_hints = M.mark_hints_line(reg, i, lines[i])
    hints[i] = line_hints

    for j = 1, #line_hints do
      local w = line_hints[j]
      indirect_hints[#indirect_hints + 1] = { i = i; j = j; dist = manh_dist(cursor_pos, { w.line, w.col }) }
    end
  end

  local dist_comparison = nil
  if reverse_distribution then
    dist_comparison = function (a, b) return a.dist > b.dist end
  else
    dist_comparison = function (a, b) return a.dist < b.dist end
  end

  table.sort(indirect_hints, dist_comparison)

  -- generate permutations and update the lines with hints
  local perms = perm.permutations(keys, #indirect_hints, opts)
  for i, indirect in pairs(indirect_hints) do
    hints[indirect.i][indirect.j].hint = tbl_to_str(perms[i])
  end

  return hints
end

-- Create the lines for the hint buffer.
function M.create_buffer_lines(buf_id, buf_width, buf_height, hints)
  local lines = {}
  for line = 1, buf_height do
    local col = 1
    local content = ''

    for _, w in pairs(hints[line]) do
      -- put spaces until we hit the beginning of the word
      if col < w.col then
        content = content .. string.rep(' ', w.col - col)
      end

      content = content .. w.hint
      col = w.col + #w.hint
    end

    if col < buf_width then
      content = content .. string.rep(' ', buf_width - col)
    end

    lines[line] = content
  end

  return lines
end

return M
