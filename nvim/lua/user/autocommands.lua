vim.cmd [[
  augroup _general_settings
    autocmd!
    autocmd FileType qf,help,man,lspinfo nnoremap <silent> <buffer> q :close<CR> 
    autocmd TextYankPost * silent!lua require('vim.highlight').on_yank({higroup = 'Visual', timeout = 200}) 
    autocmd BufWinEnter * :set formatoptions-=cro
    autocmd FileType qf set nobuflisted
  augroup end
 
  augroup lsp
    au!
    au FileType java,scala,sbt lua require("metals").initialize_or_attach({})
  augroup end 
  
  augroup _python
    autocmd!
    autocmd FileType python setlocal colorcolumn=99
    autocmd FileType python setlocal shiftwidth=4
    autocmd FileType python setlocal tabstop=4
    autocmd FileType python setlocal expandtab
  augroup end

  augroup CIndentation
      autocmd!
      autocmd FileType c setlocal shiftwidth=2 tabstop=2 expandtab
  augroup END

  augroup _git
    autocmd!
    autocmd FileType gitcommit setlocal wrap
    autocmd FileType gitcommit setlocal spell
  augroup end

  augroup _markdown
    autocmd!
    autocmd FileType markdown setlocal wrap
    autocmd FileType markdown setlocal spell
  augroup end

  augroup _auto_resize
    autocmd!
    autocmd VimResized * tabdo wincmd = 
  augroup end

  augroup _alpha
    autocmd!
    autocmd User AlphaReady set showtabline=0 | autocmd BufUnload <buffer> set showtabline=2
  augroup end
]]

-- Autoformat
-- augroup _lsp
--   autocmd!
--   autocmd BufWritePre * lua vim.lsp.buf.formatting()
-- augroup end
