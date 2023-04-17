--design choices/limits
--* sudo runs in a tty process
--* sudo should run in foreground
--* singleton
--* not work with other PAMs: u2f
--
-- credits:
--   this plugin is inspired by @asn from matrix nvim room
--   https://git.cryptomilk.org/users/asn/dotfiles.git/tree/nvim/.config/nvim/lua/utils.lua
--
--todo:
--* why sudo will not ask user to enter password every time in shell?
--* lock the buffer with &modifiable

local cthulhu = require("cthulhu")
local fs = require("infra.fs")
local ex = require("infra.ex")
local uv = vim.loop
local jelly = require("infra.jellyfish")("sudo_write")

local api = vim.api

---@param output string[]
---@param gold string
---@return boolean
local function output_contains(output, gold)
  for _, line in pairs(output) do
    if string.find(line, gold, 1, true) then return true end
  end
  return false
end

---@param args string[]
---@param callback fun(exit_code: number)
local function sudo(args, callback)
  local cmd = { "sudo", unpack(args) }
  assert(#cmd > 1)

  local bufnr, win_id
  local term, job
  local term_width, term_height

  do
    local cols, lines = vim.o.columns, vim.o.lines
    term_width = math.min(cols, math.max(math.floor(cols * 0.8), 100))
    term_height = math.min(lines, math.max(math.floor(lines * 0.3), 5))
  end

  bufnr = api.nvim_create_buf(false, true)

  local function show_prompt()
    if not (win_id and api.nvim_win_is_valid(win_id)) then
      local cols, lines = vim.o.columns, vim.o.lines
      local width = term_width + 2
      local height = term_height + 2
      local x = math.floor((cols - width) / 2)
      local y = lines - height
      win_id = api.nvim_open_win(bufnr, true, {
        relative = "editor",
        style = "minimal",
        row = y,
        col = x,
        width = width,
        height = height,
      })
    else
      api.nvim_set_current_win(win_id)
    end
    vim.cmd.startinsert()
  end

  term = api.nvim_open_term(bufnr, {
    on_input = function(_, _, _, data)
      vim.fn.chansend(job, data)
      if data == "\r" then vim.schedule(function()
        api.nvim_win_close(win_id, false)
        win_id = nil
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
      if win_id and api.nvim_win_is_valid(win_id) then api.nvim_win_close(win_id, false) end
      vim.fn.chanclose(term)
      api.nvim_buf_delete(bufnr, { force = false })
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

  bufnr = bufnr or api.nvim_get_current_buf()

  local outfile
  do
    local bufname = api.nvim_buf_get_name(bufnr)
    if bufname == "" then return jelly.err("this is an unnamed buffer") end
    if fs.is_absolute(bufname) then
      outfile = bufname
    else
      outfile = vim.fn.fnamemodify("%:p", outfile)
    end
  end

  local tmpfpath
  do
    tmpfpath = os.tmpname()
    assert(cthulhu.nvim.dump_buffer(bufnr, tmpfpath))
  end

  sudo({ "sudo", "dd", "if=" .. tmpfpath, "of=" .. outfile }, function(exit_code)
    locked = false
    assert(uv.fs_unlink(tmpfpath))
    if exit_code ~= 0 then return end
    api.nvim_buf_call(bufnr, function() ex("edit!") end)
  end)
end
