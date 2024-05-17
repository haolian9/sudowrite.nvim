lua port of `command! W w !sudo tee % > /dev/null`

(yet it has heavy dependencies now, [this gist](https://gist.github.com/haolian9/ac7fa319308e1e9ece18fb329fbf5711) may inspire you a simpler impl.)

## status
* just works
* the use of ffi may crash nvim

## prerequisites
* nvim 0.9.*
* haolian9/infra.nvim
* haolian9/cthulhu.nvim

## usage
* `:lua require'sudowrite'(api.nvim_get_current_buf())`

## credits:
this plugin is inspired by @asn from matrix nvim room: https://git.cryptomilk.org/users/asn/dotfiles.git/tree/nvim/.config/nvim/lua/utils.lua
