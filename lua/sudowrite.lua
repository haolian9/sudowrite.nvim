--design choices/limits
--* sudo runs in a tty process
--* sudo should run in foreground
--* singleton
--* not work with other PAMs: u2f
--* no lock, snapshot current content of the buffer being used
--
--known limits
--* not work on file with immutable flag `chattr +i`
--
-- credits:
--   this plugin is inspired by @asn from matrix nvim room
--   https://git.cryptomilk.org/users/asn/dotfiles.git/tree/nvim/.config/nvim/lua/utils.lua
--
--todo: reuse tty to avoid sudo asking input password every time

local cthulhu = require("cthulhu")
local bufpath = require("infra.bufpath")
local bufrename = require("infra.bufrename")
local ex = require("infra.ex")
local iuv = require("infra.iuv")
local jelly = require("infra.jellyfish")("sudowrite")
local mi = require("infra.mi")
local ni = require("infra.ni")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local strlib = require("infra.strlib")

---@param output string[]
---@param gold string
---@return boolean
local function output_contains(output, gold)
  for _, line in ipairs(output) do
    if strlib.contains(line, gold) then return true end
  end
  return false
end

---@param args string[]
---@param callback fun(exit_code: number)
local function sudo(args, callback)
  local cmd = { "sudo", unpack(args) }
  assert(#cmd > 1)

  local bufnr, winid
  local term, job
  local term_width, term_height

  do
    local cols, lines = vim.go.columns, vim.go.lines
    term_width = math.min(cols, math.max(math.floor(cols * 0.8), 100))
    term_height = math.min(lines, math.max(math.floor(lines * 0.3), 5))
  end

  bufnr = ni.create_buf(false, true) --no ephemeral here
  bufrename(bufnr, string.format("sudo://%s", table.concat(args, " ")))

  local function show_prompt()
    if not (winid and ni.win_is_valid(winid)) then
      local width = term_width + 2
      local height = term_height + 2
      winid = rifts.open.fragment(bufnr, true, { relative = "editor" }, { width = width, height = height, horizontal = "mid", vertical = "bot" })
    else
      ni.set_current_win(winid)
    end
    ex("startinsert")
  end

  term = ni.open_term(bufnr, {
    on_input = function(_, _, _, data)
      vim.fn.chansend(job, data)
      if data == "\r" then vim.schedule(function()
        ni.win_close(winid, false)
        winid = nil
      end) end
    end,
  })

  job = vim.fn.jobstart(cmd, {
    pty = true,
    width = term_width,
    height = term_height,
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = false,
    env = { LANG = "C" },
    on_exit = function(_, exit_code, _)
      if winid and ni.win_is_valid(winid) then ni.win_close(winid, false) end
      vim.fn.chanclose(term)
      ni.buf_delete(bufnr, { force = false })
      callback(exit_code)
    end,
    on_stdout = function(_, data, _)
      vim.fn.chansend(term, data)
      if output_contains(data, "[sudo] password for") then show_prompt() end
    end,
    on_stderr = function(_, data, _)
      if output_contains(data, "[sudo] password for") then show_prompt() end
      vim.fn.chansend(term, data)
    end,
  })
end

local locked = false

return function(bufnr)
  assert(not locked)
  locked = true

  bufnr = mi.resolve_bufnr_param(bufnr)

  local outfile = bufpath.file(bufnr)
  if outfile == nil then return jelly.info("no file associated to buf#%d", bufnr) end

  local tmpfpath = os.tmpname()
  assert(cthulhu.nvim.dump_buffer(bufnr, tmpfpath))

  sudo({ "dd", "if=" .. tmpfpath, "of=" .. outfile }, function(exit_code)
    locked = false
    iuv.fs_unlink(tmpfpath)
    if exit_code ~= 0 then return jelly.warn("unable to write %s", outfile) end
    prefer.bo(bufnr, "modified", false)
  end)
end
