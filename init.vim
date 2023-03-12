let mapleader = ';'
nnoremap ; <Leader>

" config defaults
set runtimepath^=$HOME\AppData\Local\nvim\init.vim
set runtimepath+=~\vimfiles
let &packpath = &runtimepath

" basic text wrap and editing

set nocompatible
filetype plugin on

set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
syntax on

" appearence

set fillchars+=eob:\ 
set laststatus=0

" vimplug


call plug#begin('C:\Users\b\AppData\Local\nvim-data\plugged')

Plug 'SirVer/ultisnips'

" Snippets are separated from the engine. Add this if you want them:
Plug 'honza/vim-snippets'

" Trigger configuration. You need to change this to something other than <tab> if you use one of the following:
" - https://github.com/Valloric/YouCompleteMe
" - https://github.com/nvim-lua/completion-nvim

Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && yarn install' }

Plug 'vimwiki/vimwiki'

Plug 'Pocco81/auto-save.nvim'

call plug#end()

let g:vimwiki_list = [{'path': '~/vimwiki/',
                      \ 'syntax': 'markdown', 'ext': '.md'}]
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"


