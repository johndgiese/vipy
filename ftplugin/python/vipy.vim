" PYTHON FILE MAPPINGS
nnoremap <silent> <F5> :wa<CR>:py run_this_file()<CR><ESC>l
inoremap <silent> <F5> <ESC>:wa<CR>:py run_this_file()<CR>li
noremap <silent> K :py get_doc_buffer()<CR>
vnoremap <silent> <F9> y:py run_these_lines()<CR><ESC>
nnoremap <silent> <F9> :py run_this_line()<CR><ESC>j
noremap <silent> <F12> :py toggle_vib()<CR>
inoremap <silent> <F12> <ESC>:py toggle_vib()<CR>
inoremap <silent> <S-CR> <ESC>:set nohlsearch<CR>V?^\n<CR>:python run_these_lines()<CR>:let @/ = ""<CR>:set hlsearch<CR>Go<ESC>o

" CELL MODE MAPPINGS
nnoremap <silent> <S-CR> :py run_cell()<CR><ESC>
nnoremap <silent> <C-CR> :py run_cell(progress=True)<CR><ESC>
inoremap <silent> <S-CR> <ESC>:py run_cell()<CR><ESC>i
inoremap <silent> <C-CR> <ESC>:py run_cell(progress=True)<CR><ESC>i
vnoremap <silent> <S-CR> :py run_cell()<CR><ESC>gv
vnoremap <silent> <C-CR> :py run_cell(progress=True)<CR><ESC>gv

" AUTO COMPLETE
fun! CompleteIPython(findstart, base)
    if a:findstart
        " locate the start of the word
        let line = getline('.')
        let start = col('.') - 1
        python complete_type = 'normal'
        while start > 0
            "python vib.append('cc: %s' % vim.eval('line[start-1]'))
            if line[start-1] !~ '\w\|\.'
                if line[start-1] == '('
                    python complete_type = 'argument'
                endif
                break
            endif
            let start -= 1
        endwhile
        return start
    else
        let res = []

        python << endpython
cl = vim.current.line
base = vim.eval('a:base')
completions = ['']
if complete_type in ['method','normal']:
    msg_id = km.shell_channel.complete(base, cl, vim.eval("col('.')"))
    try:
        m = get_child_msg(msg_id)
        matches = m['content']['matches']
        matches.insert(0, base) # the "no completion" version
        if in_vipy:
            completions = [s.encode(vim_encoding) for s in matches]
        else:
            completions = [s.encode(vim_encoding) for s in matches if s[0] and s[0] != '%']
    except Empty:
        echo("no reply from IPython kernel")
elif complete_type == 'argument':
    # TODO: make this more robust (perhaps by inspecting the function directly, instead of using ipython...
    count = int(vim.eval("col('.')")) - 2 # one for indexing, one for cursor
    o_start = count
    o_end = count
    while count > 0:
        if cl[count] == '(':
            o_end = count
        elif not indent_or_period.match(cl[count]):
            o_start = count
            break
        count = count - 1
    oname = cl[o_start:o_end]
    # vib.append(oname)

    # request object info from ipython
    msg_id = km.shell_channel.object_info(oname, detail_level=1)

    try:
        m = get_child_msg(msg_id)
        # vib.append(repr(m))
        if m['content']['found'] and m['content']['argspec']:
            completions = m['content']['argspec']['args']
    except Empty:
        echo("no reply from IPython kernel") 

for c in completions:
    vim.command('call add(res,"'+c+'")')
endpython

        return res
    endif
endfun
