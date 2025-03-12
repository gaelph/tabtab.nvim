" Prevent loading the plugin multiple times
if exists('g:loaded_tabtab')
  finish
endif
let g:loaded_tabtab = 1

" Define the command to open the log file
command! -nargs=0 -bar TabTabLogs lua require("tabtab.log").open()

" Define the command to clear the log file
command! -nargs=0 -bar TabTabClearLogs lua require("tabtab.log").clear()
