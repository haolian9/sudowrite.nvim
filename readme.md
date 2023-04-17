lua port of `command! W w !sudo tee % > /dev/null`


## status
* just works (tm)
* it heavily uses ffi which may crash nvim

## prerequisites
* nvim 0.8.*
* haolian9/infra.nvim
* haolian9/cthulhu.nvim

## usage
* `:lua require'sudo_write'(api.nvim_get_current_buf())`

## credits:
this plugin is inspired by @asn from matrix nvim room: https://git.cryptomilk.org/users/asn/dotfiles.git/tree/nvim/.config/nvim/lua/utils.lua
