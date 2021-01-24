call plug#begin()
Plug 'sheerun/vim-polyglot'
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
Plug 'preservim/nerdtree'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'folti/showmarks'
Plug 'ap/vim-buftabline'
Plug 'quramy/tsuquyomi'
Plug 'tpope/vim-fugitive'
Plug 'itchyny/lightline.vim'
Plug 'editorconfig/editorconfig-vim'
Plug 'prettier/vim-prettier', { 'do': 'npm install', 'for': ['javascript', 'typescript', 'css', 'json', 'vue', 'yaml', 'html' ] }
Plug 'ycm-core/YouCompleteMe', { 'do': './install.py --tern-completer' }
Plug 'jiangmiao/auto-pairs'
Plug 'tpope/vim-commentary'
Plug 'konfekt/vim-scratchpad'
Plug 'adampresley/vim-markdown-preview-mdtohtml'
Plug 'jeffkreeftmeijer/vim-numbertoggle'
Plug 'thaerkh/vim-workspace'
Plug 'OmniSharp/omnisharp-vim'
Plug 'phanviet/vim-monokai-pro'
call plug#end()

" Automatically source vimrc on save
augroup reload_vimrc
    autocmd!
    autocmd BufWritePost vimrc source ~/.vimrc
    " autocmd BufWritePost vimrc AirlineRefresh
augroup END

" Restore cursor position on buffer navigation
:autocmd BufEnter * silent! normal! g`"

" cursor to the last line when reopening a file
augroup line_jump_on_open
    au!
    au BufReadPost *
        \ if line("'\"") > 0 && line("'\"") <= line("$") |
        \     execute 'normal! g`"zvzz' |
        \ endif
 augroup END

" Use system clipboard
set clipboard=unnamed

" Autosave when switching buffers
set autowrite
set autowriteall

" Change LEADER character to comma
let mapleader = ','

" Set our color scheme/theme
set termguicolors 
colorscheme monokai_pro

" Make backspace better IMHO
set backspace=indent,eol,start

" Tabs and stuff
set tabstop=3
set shiftwidth=3
set noexpandtab

" Workspace settings
let g:workspace_session_directory = $HOME . '/.vim/sessions/'
nnoremap <leader>tw :ToggleWorkspace<cr>

" Keys for splitting windows
nmap <leader>sv :vsplit<cr>
nmap <leader>sh :split<cr>

" Keys for wrapping text in quotes and other stuff
nmap <leader>' ciw'<C-r>"'<esc>
nmap <leader>" ciw"<C-r>""<esc>
nmap <leader>` ciw`<C-r>"`<esc>

autocmd bufread *.md nmap <leader>* ciw**<C-r>"**<esc>
autocmd bufread *.md nmap <leader>_ ciw*<C-r>"*<esc>

autocmd bufread *.html nmap <leader>s ciw<strong><C-r>"</strong><esc>
autocmd bufread *.html nmap <leader>l ciw<li><C-r>"</li><esc>

autocmd bufread *.js nmap <leader>l iconsole.log();<esc>
autocmd bufread *.ts nmap <leader>l iconsole.log();<esc>

vmap <leader>' c'<C-r>"'<esc>
vmap <leader>" c"<C-r>""<esc>
vmap <leader>` c`<C-r>"`<esc>

autocmd bufread *.md vmap <leader>* c**<C-r>"**<esc>
autocmd bufread *.md vmap <leader>_ c*<C-r>"*<esc>

autocmd bufread *.html vmap <leader>s c<strong><C-r>"</strong><esc>
autocmd bufread *.html vmap <leader>l c<li><C-r>"</li><esc>
autocmd bufread *.html vmap <leader>p c<p><C-r>"</p><esc>

" Line numbers
:set number relativenumber

" Key for Markdown Preview
let vim_markdown_preview_mdtohtml_css='~/Documents/Dev-Setup/markdown-css/github.css'

" Key to toggle NERDTree
nmap <leader>1 :NERDTreeToggle<cr>
let g:NERDTreeWinSize=60
let NERDTreeQuitOnOpen=1
let NERDTreeAutoDeleteBuffer=1
let NERDTreeMinimalUI=1
let NERDTreeDirArrows=1
" autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTreeType") && b:NERDTreeType == "primary") | q | endif

" Turn off preview for autompleters
set completeopt-=preview

" Keys for Fuzzy Finder
nnoremap <C-p> :Files<cr>
nnoremap <C-r> :BLines<cr>
nmap <leader>b :Buffers<cr>
nmap <leader>ff :Rg<cr>

let g:fzf_history_dir = '~/.fzf-history'

" Keys to navigate buffers using Buftabline
set hidden
nnoremap } :bnext<cr>
nnoremap { :bprev<cr>
nmap <leader>w :bw<cr>

" Keys for navigating windows
nmap <leader>nw <C-w>w
nmap <leader>cw <C-w>c

" Keys and settings for Go
au FileType go nmap <leader>gi <Plug>(go-imports)
au FileType go nmap <leader>gg <Plug>(go-generate)
au FileType go nmap <leader>gimpl <Plug>(go-implements)
au FileType go nmap <leader>gc <Plug>(go-callers)
au FileType go nmap <leader>gat :GoAddTags<cr>
au FileType go nmap <leader>gr <Plug>(go-rename)
au FileType go nmap <leader>gfs :GoFillStruct<cr>

let g:go_addtags_transform = 'camelcase'

" Keys and settings for Typescript
au FileType typescript nmap <buffer> <leader>tr <Plug>(TsuquyomiRenameSymbol)
au FileType typescript nmap <buffer> <leader>ti <Plug>(TsuquyomiImport)

let g:tsuquyomi_disable_quickfix = 1

" Keys and settings for C#
au FileType cs nmap <leader>cf <Plug>(omnisharp_code_format)
au FileType cs nmap <leader>cr <Plug>(omnisharp_rename)
au FileType cs nmap <leader>ci <Plug>(omnisharp_fix_usings)

" Keys and settings for Fugitive
nmap <leader>gd :Git diff<cr>

" Fix issues with commenting script in Vue files
autocmd FileType vue setlocal commentstring=//\ %s

" Keys to move lines and blocks up and down
nnoremap <C-j> :m .+1<CR>==
nnoremap <C-k> :m .-2<CR>==
vnoremap <C-j> :m '>+1<CR>gv=gv
vnoremap <C-k> :m '<-2<CR>gv=gv

" Ignore case in searches
:set ignorecase

" Statusline configuration. Using lightline
set laststatus=2
set noshowmode

let g:lightline = {
			\ 'active': {
			\		'left': [ [ 'mode', 'paste' ],
			\					[ 'gitbranch', 'readonly', 'absolutepath', 'modified' ] ]
			\ },
			\ 'component_function': {
			\ 		'gitbranch': 'FugitiveHead',
			\ },
			\ 'colorscheme': 'monokai_pro',
			\ }

" Remember marks
set viminfo='100,f1

" Disable beeping and flashing
set noerrorbells visualbell t_vb=
if has('autocmd')
	autocmd GUIEnter * set visualbell t_vb=
endif

