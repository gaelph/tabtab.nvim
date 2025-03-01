" zeta.nvim plugin registration
" Prevents loading the plugin multiple times
if exists('g:loaded_zeta')
    finish
endif
let g:loaded_zeta = 1

" Plugin commands
command! ZetaExample lua require('zeta').example_function()

" You can add more commands, autocommands, or other Vim script here
