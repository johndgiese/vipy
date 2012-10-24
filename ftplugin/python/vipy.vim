" PYTHON FILE MAPPINGS
nnoremap <silent> <buffer> <leader>5 :wa<CR>:py run_this_file()<CR><ESC>l
vnoremap <silent> <buffer> <leader>5 y:py run_these_lines()<CR><ESC>
" TODO: make K print currentword? in the buffer
" noremap  <silent> K :py get_doc_buffer()<CR>
nnoremap <silent> <buffer> <F9> :py run_this_line()<CR><ESC>j
noremap  <silent> <buffer> <F12> :py toggle_vib()<CR>
inoremap <silent> <buffer> <F12> <ESC>:py toggle_vib()<CR>
nnoremap <silent> <buffer> <F10> :py db_step()<CR>
nnoremap <silent> <buffer> <F11> :py db_stepinto()<CR>
nnoremap <silent> <buffer> <C-F11> :py db_stepout()<CR>
nnoremap <silent> <buffer> <leader>% :py db_quit()<CR>

" CELL MODE MAPPINGS
nnoremap <expr> <buffer> <silent> <S-CR> pumvisible() ? "\<ESC>:py print_completions(invipy=False)\<CR>i" : "\<ESC>:py run_cell()\<CR>\<ESC>i"
nnoremap <silent> <buffer> <C-CR> :py run_cell(progress=True)<CR><ESC>
inoremap <expr> <silent> <buffer> <S-CR> pumvisible() ? "\<ESC>:py print_completions(invipy=False)\<CR>i" : "\<ESC>:py run_cell()\<CR>\<ESC>i"
inoremap <silent> <buffer> <C-CR> <ESC>:py run_cell(progress=True)<CR><ESC>i
vnoremap <silent> <buffer> <S-CR> :py run_cell()<CR><ESC>gv
vnoremap <silent> <buffer> <C-CR> :py run_cell(progress=True)<CR><ESC>gv

" AUTO COMPLETE
fun! CompleteIPython(findstart, base)
    if a:findstart
        " locate the start of the word
        let line = getline('.')
        let start = col('.') - 1
        python complete_type = 'normal'
        while start > 0
            "python vib.append('cc: %s' % vim.eval('line[start-1]'))
            if line[start-1] !~ '\w\|\.\|\/'
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
indent_or_period = re.compile(r'[a-zA-Z0-9_.]')
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
