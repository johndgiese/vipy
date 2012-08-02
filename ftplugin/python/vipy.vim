" TODO: add debugger capabilites
" TODO: figure out what is wrong with ion()
" TODO: handle multi-line input_requests (is this ever possible anyways?)
" TODO: make vim-only commands work even if there are multiple entered
" togethre
" TODO: fix cursor issue
" TODO: better tab complete which can tell if you are in a function call, and return arguments as appropriatey)
" TODO: use the ipython color codes as syntax blocks in vib
" TODO: make sure everything works on mac and linux
" TODO: when there is really long output, and the user is in the vib, then
" make it act like less (so that you can scroll down)
" TODO: ipython won't close with S-F12 if figures are open; figure out why and
" fix
" FIXME: running a file with F5 places you in insert mode
" FIXME: the color coding breaks sometimes when if 
" TODO: prevent F9 and other mappings from throwing warnings when python is
" not open
" FIXME: there is a bug that will occur if the vipy buffer isn't shown
" in any window, and you press F12 (I think it only occurs if you have
" changed the vim path using :cd new_directory) The bufexplorer doesn't work
" when this bug occurs
" TODO: handle copy-pasting into vib better
" TODO: figure out a way to tell if the kernel is closed...
"
" TODO: better documentation
" TODO: user options
" TODO: write the user guide, including advantages of vipy over other
" setups

if !has('python')
    " exit if python is not available.
    finish
endif

" add this back when I am done developing
"if exists("b:did_vimipy")
"   finish
"endif
"let b:did_vimipy = 1

let g:ipy_status="idle"

" let the user specify the IPython profile they want to use
if !exists('g:vipy_profile')
    let g:vipy_profile = 'default'
endif

if !exists('g:vipy_clean_connect_files')
    let g:vipy_clean_connect_files = 1
endif


"try
python << EOF
import vim
import sys
import re
import os
from os.path import basename
try:
    import IPython
    if float(IPython.__version__) < 0.13:
        vim.command("echoe('vipy requires IPython >= 0.13')")
        raise ImportErorr('vipy requires IPython >= 0.13')
except:
    # let vim's try-catch handle this
    raise

try:
    from IPython.zmq.blockingkernelmanager import BlockingKernelManager, Empty
except ImportError:
    vim.command("echoe('You must have pyzmq >= 2.1.4 installed so that vim can communicate with IPython.')")
    if vim.eval("has('win64')"):
        vim.command("echoe('There is a known issue with pyzmq on 64 bit windows machines.')")
    raise
    
from IPython.lib.kernel import find_connection_file

debugging = False
in_debugger = False
monitor_subchannel = True   # update vipy 'shell' on every send?
run_flags= "-i"             # flags to for IPython's run magic when using <F5>
current_line = ''
vib_ns = 'normalstart'      # used to signify the start of normal highlighting
vib_ne = 'normalend'        # signify the end of normal highlighting
vib_es = 'errorstart'
vib_ee = 'errorend'

try:
    status
except:
    status = 'idle'
try:
    length_of_last_input_request
except: 
    length_of_last_input_request = 0
try:
    vib
except:
    vib = False
try:
    vihb
except:
    vihb = False
try:
    km
except NameError:
    km = None
try:
    km_started_by_vim
except:
    km_started_by_vim = False

# get around unicode problems when interfacing with vim
vim_encoding = vim.eval('&encoding') or 'utf-8'

try:
    sys.stdout.flush
except AttributeError:
    # IPython complains if stderr and stdout don't have flush
    # this is fixed in newer version of Vim
    class WithFlush(object):
        def __init__(self,noflush):
            self.write=noflush.write
            self.writelines=noflush.writelines
        def flush(self):
            pass
    sys.stdout = WithFlush(sys.stdout)
    sys.stderr = WithFlush(sys.stderr)

## STARTUP and SHUTDOWN
def startup():
    global km, fullpath, km_started_by_vim
    if not km:
        vim.command("augroup vimipython")
        vim.command("au CursorHold * :python update_subchannel_msgs()")
        vim.command("au FocusGained *.py :python update_subchannel_msgs()")
        vim.command("au filetype python setlocal completefunc=CompleteIPython")
        # run shutdown sequense
        vim.command("au VimLeavePre :python shutdown()")
        vim.command("augroup END")

        count = 0
        profile = vim.eval('g:vipy_profile')
        fullpath = None
        try:
            # see if there is already an IPython instance open ...
            fullpath = find_connection_file('', profile=profile)
        except: # ... if not start one
            ipy_args = '--profile=' + profile
            # TODO: add custom ipython directory
            #if vim.eval("exists('g:vipy_ipy_dir')"):
            #    ipy_dir = vim.eval('g:vipy_ipy_dir')
            #    ipy_args += ' --ipython-dir=' + ipy_dir

            if vim.eval("has('win32')") or vim.eval("has('win64')"):
                vim.command('!start /min ipython kernel ' + ipy_args)
            elif vim.eval("has('unix')") or vim.eval("has('mac')"):
                vim.command('!ipython kernel ' + ipy_args)
                
            # try to find connection file (sometimes you need to wait a bit)
            count = 0
            while count < 10:
                try:
                    fullpath = find_connection_file('', profile=profile)
                    break
                except:
                    count = count + 1
                    vim.command('sleep 1')
        if fullpath:
            km = BlockingKernelManager(connection_file = fullpath)
            km.load_connection_file()
            km.start_channels()
            km_started_by_vim = True
        else:
            echo("Couldn't connect to vim-ipython.")
            if profile != 'default':
                echo("Is it possible that the profile specified with g:vipy_profile doesn't exist?  You can create ipython profiles at the command line using: ipython profile create profilename")
            return

        vib = get_vim_ipython_buffer()
        if not vib:
            setup_vib()
        else:
            echo('It appears that there is already a file named vipy.py open!  This will cause errors unless it is generated by the vipy plugin (i.e. if it is a regular file named vipy.py).')
        goto_vib()

        # Update the vipy shell when the cursor is not moving
        # the cursor hold is updated 3 times a second (maximum), but it doesn't
        # update if you stop moving
        vim.command("set updatetime=333") 
    else:
        echo('Vipy has already been started!  Press SHIFT-F12 to close the current seeion.')

def shutdown():
    global km, in_debugger, vib, vihb, km_started_by_vim
    
    # shutdown the kernel if we started it
    if km_started_by_vim:
        try:
            km.shell_channel.shutdown()
        except:
            echo('The kernel must have already shut down.')
        if vim.eval('g:vipy_clean_connect_files'):
            import os
            connect_dir = os.path.dirname(fullpath)
            connect_files = [p for p in os.listdir(connect_dir) if p.endswith('.json')]
            for p in connect_files:
                os.remove(os.path.join(connect_dir, p))

    del(km)
    km = None
    
    # wipe the buffer
    try:
        if vib:
            if len(vim.windows) == 1:
                vim.command('bprevious')
            vim.command('bw ' + vib.name)
            vib = None
    except:
        echo('The vipy buffer must have already been closed.')
    try:
        if vihb:
            if len(vim.windows) == 1:
                vim.command('bprevious')
            vim.command('bw ' + vihb.name)
            vihb = None
    except:
        vihb = None
    vim.command("au! vimipython")

def km_from_connection_file():
    return

def setup_vib():
    """ Setup vib (vipy buffer), that acts like a prompt. """
    global vib, vib_ns, vib_ne, vib_ee, vib_es
    vim.command("rightbelow vnew vipy.py")
    # set the global variable for everyone to reference easily
    vib = get_vim_ipython_buffer()
    new_prompt(append=False)

    vim.command("setlocal nonumber")
    vim.command("setlocal bufhidden=hide buftype=nofile ft=python noswf nobl")
    # turn of auto indent (there is some custom indenting that accounts
    # for the prompt).  See vim-tip 330
    vim.command("setl noai nocin nosi inde=") 
    vim.command("syn match Normal /^>>>/")

    # mappings to control sending stuff from vipy
    vim.command("inoremap <buffer> <silent> <s-cr> <ESC>:py shift_enter_at_prompt()<CR>")
    vim.command("nnoremap <buffer> <silent> <s-cr> <ESC>:py shift_enter_at_prompt()<CR>")
    vim.command("inoremap <buffer> <silent> <cr> <ESC>:py enter_at_prompt()<CR>")

    # setup history mappings etc.
    enter_normal(first=True)

    # add and auto command, so that the cursor always moves to the end
    # upon entereing the vipy buffer
    vim.command("au WinEnter <buffer> :python insert_at_new()")
    # not working; the idea was to make
    # vim.command("au InsertEnter <buffer> :py if above_prompt(): vim.command('normal G$')")
    vim.command("setlocal statusline=\ \ \ %-{g:ipy_status}")
    
    # handle syntax coloring a little better
    if vim.eval("has('conceal')"): # if vim has the conceal option
        setup_highlighting()
    else: # otherwise, turn of the ns, ne markers
        vib_ns = ''
        vib_ne = ''
        vib_es = ''
        vib_ee = ''

def setup_highlighting():
    """ Setup the normal highlighting system for the current buffer. """
    vim.command("syn region VipyNormal matchgroup=Hidden start=/^" + vib_ns + "/ end=/" + vib_ne + "$/ concealends contains=VipyNormalTrans")
    vim.command("syn region VipyNormalTrans start=/^>>>\ \|^\.\.\.\ / end=/$/ contained transparent contains=ALLBUT,pythonDoctest,pythonDoctestValue")
    vim.command("syn region VipyError matchgroup=Hidden start=/^" + vib_es + "/ end=/" + vib_ee + "$/ concealends contains=VipyErrorTrans")
    vim.command("syn region VipyErrorTrans start=/^ \+\d\+ \|^-\+> \d\+ / end=/$/ contained transparent contains=ALLBUT,pythonDoctest,pythonDoctestValue")
    vim.command("hi link VipyNormal Normal")
    vim.command("hi VipyError guibg=NONE guifg=#FF7777 gui=NONE")
    vim.command("hi link VipyNormalTrans Normal")
    vim.command("hi link VipyErrorTrans Normal")
    vim.command("setlocal conceallevel=3")
    vim.command('setlocal concealcursor=nvic')
    return


def enter_normal(first=False):
    global vib_map, in_debugger
    in_debugger = False
    vib_map = "on"
    in_debugger = False
    # mappings to control history
    vim.command("inoremap <buffer> <silent> <up> <ESC>:py prompt_history('up')<CR>")
    vim.command("inoremap <buffer> <silent> <down> <ESC>:py prompt_history('down')<CR>")

    # make some normal vim commands convenient when in the vib
    vim.command("nnoremap <buffer> <silent> dd cc>>> ")
    vim.command("noremap <buffer> <silent> <home> 0llll")
    vim.command("inoremap <buffer> <silent> <home> <ESC>0llla")
    vim.command("noremap <buffer> <silent> 0 0llll")

    # unmap debug codes
    if not first:
        try:
            vim.command("nunmap <F10>")
            vim.command("nunmap <F11>")
            vim.command("nunmap <C-F11>")
            vim.command("nunmap <S-F5>")
        except vim.error:
            pass

def enter_debug():
    """ Remove all the convenience mappings. """
    global vib_map, in_debugger
    vib_map = "off"
    in_debugger = True
    try:
        vim.command("iunmap <buffer> <silent> <up>")
        vim.command("iunmap <buffer> <silent> <down>")
        vim.command("iunmap <buffer> <silent> <right>")
        vim.command("nunmap <buffer> <silent> dd")
        vim.command("nunmap <buffer> <silent> <home>")
        vim.command("iunmap <buffer> <silent> <home>")
        vim.command("nunmap <buffer> <silent> 0")
    except vim.error:
        pass

    vim.command("nnoremap <F10> :py db_step()<CR>")
    vim.command("nnoremap <F11> :py db_stepinto()<CR>")
    vim.command("nnoremap <C-F11> :py db_stepout()<CR>")
    # vim.command("nnoremap <F5> :py db_continue()<CR>") # this is set below
    vim.command("nnoremap <S-F5> :py db_quit()<CR>")

## DEBUGGING
""" I think the best way to do visual debugging will be to use marks for break
points.  Originally I wanted to use signs, but it doesn't seem like there is
any way to access there locations when you are in python.  Marks you can
access, and set.  You can access them directly, you can set them using the
setpos() vim function.  I think marks in combination with the showmarks
plugin, will allow us to make a really good visual debugger that is laid on
top of pdb. """
# TODO: figure out a way to know when you are out of the debugger

vim.command("sign define pypc texthl=ProgCount text=>>")
vim.command("hi ProgCount guibg=#000000 guifg=#00FE33 gui=bold cterm=NONE ctermfg=red ctermbg=NONE")

bps = []

def update_pg():
    """ Place a sign in the file specified by the last raw_input request with pdb"""
    for i in range(len(vib)):
        pass


def signs_to_bps():
    pass

def db_check(fun):
    """ Check whether in debug mode and print prompt. """
    def wrapper():
        global in_debugger
        if in_debugger:
            prompt = fun()
        else:
            return

    return wrapper

@db_check
def db_step():
    km.stdin_channel.input('n')
    return 'next'

@db_check
def db_stepinto():
    km.stdin_channel.input('s')
    return 'step'

@db_check
def db_stepout():
    km.stdin_channel.input('unt')
    return 'until'

def db_continue():
    global in_debugger, bps
    if not in_debugger:
        if len(bps) == 0:
            run_this_file()
            return
        msg_id = send("run -d %s" % (repr(vim.current.buffer.name)[1:-1]))
        in_debugger = True
    km.stdin_channel.input('c')
    return 'continue'

@db_check
def db_quit():
    km.stdin_channel.input('q')
    in_debugger = False
    return 'quit'

## COMMAND-LINE-HISTORY
need_new_hist = True
last_hist = []
hist_pos = 0
num_lines_added_last = 1
hist_prompt = '>>> '
hist_last_appended = ''
def prompt_history(key):
    """ Poll server for history if a new search is needed, otherwise rotate
    through matches. """

    global last_hist, hist_pos, need_new_hist, num_lines_added_last, hist_prompt, hist_last_appended
    if not at_end_of_prompt():
        r,c = vim.current.window.cursor
        if key == "up":
            if not r == 1:
                vim.current.window.cursor = (r - 1, c)
        elif key == "down":
            if not r == len(vim.current.buffer):
                vim.current.window.cursor = (r + 1, c)
        return
    if status == "busy":
        # echo("No history available because the python server is busy.")
        # the message gets overridden immedieatly when the mapping switches back to 
        # insert mode
        return
    if not vib[-1] == hist_last_appended:
        need_new_hist = True
    if need_new_hist:
        cl = vim.current.line
        if len(cl) > 4: # search for everything starting with the current line
            pat = cl[4:] + '*'
            msg_id = km.shell_channel.history(hist_access_type='search', pattern=pat)
        else: # return the last 100 inputs
            pat = ' '
            msg_id = km.shell_channel.history(hist_access_type='tail', n=50)
        hist_prompt = cl[:4] if len(cl) >= 4 else '>>> '
            
        hist = get_child_msg(msg_id)['content']['history']
        # sort the history by time
        last_hist = sorted(hist, key=hist_sort, reverse=True)
        last_hist = [hi[2].encode(vim_encoding) for hi in last_hist] + [pat[:-1]]
        need_new_hist = False
        hist_pos = 0
        num_lines_added_last = 1
    else:
        if key == "up":
            hist_pos = (hist_pos + 1) % len(last_hist)
        else: # if key == "down"
            hist_pos = (hist_pos - 1) % len(last_hist)

    # remove the previously added lines
    if num_lines_added_last > 1:
        del vib[-(num_lines_added_last - 1):]
    toadd = format_for_prompt(last_hist[hist_pos], firstline=hist_prompt)
    num_lines_added_last = len(toadd)

    vib[-1] = toadd[0]
    for line in toadd[1:]:
        vib.append(line)
    hist_last_appended = toadd[-1]

    vim.command('normal G$')
    vim.command('startinsert!')

def hist_sort(hist_item):
    """ Sort history items such that the most recent sessions has highest
    priority.
    
    hist_item is a tuple with: (session, line_number, input)
    where session and line_number increase through time. """
    return hist_item[0]*10000 + hist_item[1]

## COMMAND LINE 
numspace = re.compile(r'^[>.]{3}(\s*)')
def enter_at_prompt():
    if at_end_of_prompt():
        match = numspace.match(vib[-1])
        if match:
            space_on_lastline = match.group(1)
        else:
            space_on_lastline = ''
        vib.append('...' + space_on_lastline)
        vim.command('normal G')
        vim.command('startinsert!')
    else:
        # do a normal return FIXME
        # vim.command('call feedkeys("\<CR>")')
        vim.command('normal <CR>')

def shift_enter_at_prompt():
    """ Remove prompts and whitespace before sending to ipython. """
    if status == 'input requested':
        km.stdin_channel.input(vib[-1][length_of_last_input_request:])
    else:
        stop_str = r'>>>'
        cmds = []
        linen = len(vib)
        while linen > 0:
            # remove the last three characters
            cmds.append(vib[linen - 1][4:]) 
            if vib[linen - 1].startswith(stop_str):
                break
            else:
                linen -= 1
        cmds.reverse()

        cmds = '\n'.join(cmds)
        if cmds == 'cls' or cmds == 'clear':
            vib[:] = None # clear the buffer
            new_prompt(append=False)
            return
            #elif cmds.startswith('edit '):
            #    fnames = cmds[5:].split(' ')
            #    msg_id = km.shell_channel.execute('', user_expressions={'pwd': '%pwd'})
            #    try:
            #        pwd = get_child_msg(msg_id)
            #        vib.append(repr(pwd).splitlines())
            #        pwd = pwd['user_expressions']['pwd']
            #    except Empty:
            #        # timeout occurred
            #        return echo("no reply from IPython kernel")
            #    for fname in fnames:
            #        try:
            #            pp = os.path.join(pwd, fname)
            #            vim.command('drop ' + pp)
            #        except:
            #            vib.append(unh("Couldn't find " + pp))
            #    new_prompt()
        elif cmds.endswith('??'):
            msg_id = km.shell_channel.object_info(cmds[:-2])
            try:
                content = get_child_msg(msg_id)['content']
            except Empty:
                # timeout occurred
                return echo("no reply from IPython kernel")
            if content['found']:
                if content['file']:
                    vim.command("drop " + content['file'])
                    content = None
                else:
                    content = unh("The object doesn't have a source file associated with it.")
            else:
                content = unh("No object information was found.  Make sure that the requested object is in the interactive namespace.")
            if content:
                vib.append(content)
            new_prompt()
        elif cmds.endswith('?'):
            content = unh(get_doc(cmds[:-1]))
            if content == '':
                content =  unh('No matches found for: %s' % cmds[:-1])
            vib.append(content)
            new_prompt()
            return
        else:
            send(cmds)
            # make vim poll for a while
            ping_count = 0
            while ping_count < 30 and not update_subchannel_msgs():
                vim.command("sleep 20m")
                ping_count += 1

def new_prompt(goto=True, append=True):
    if append:
        vib.append('>>> ')
    else:
        vib[-1] = '>>> '
    if goto:
        vim.command('normal G')
        vim.command('startinsert!')

def format_for_prompt(cmds, firstline='>>> ', limit=False):
    # format and input text
    max_lines = 10
    lines_to_show_when_over = 4
    if debugging:
        vib.append('this is what is being formated for the prompt:')
        vib.append(cmds)
    if not cmds == '':
        formatted = re.sub(r'\n',r'\n... ',cmds).splitlines()
        lines = len(formatted)
        if limit and lines > max_lines:
            formatted = formatted[:lines_to_show_when_over] + ['... (%d more lines)' % (lines - lines_to_show_when_over)]
        formatted[0] = firstline + formatted[0]
        return formatted
    else:
        return [firstline]

## IPYTHON-VIM COMMUNICATION
blankprompt = re.compile(r'^\>\>\> $')
def send(cmds, *args, **kargs):
    """ Send commands to ipython kernel. 

    Format the input, then print the statements to the vipy buffer.
    """
    formatted = None
    if status == 'input requested':
        echo('Can not send further commands until you respond to the input request.')
        return 
    elif status == 'busy':
        echo('Can not send commands while the python kernel is busy.')
        return
    if not in_vipy():
        formatted = format_for_prompt(cmds, limit=True)

        # remove any prompts or blank lines
        while len(vib) > 1 and blankprompt.match(vib[-1]):
            del vib[-1]
            
        if blankprompt.match(vib[-1]):
            vib[-1] = formatted[0]
            if len(formatted) > 1:
                vib.append(formatted[1:])
        else:
            vib.append(formatted) 
    val = km.shell_channel.execute(cmds, *args, **kargs)
    return val


def update_subchannel_msgs(debug=False):
    """ This function grabs messages from ipython and acts accordinly; note
    that communications are asynchronous, and furthermore there is no good way to
    repeatedly trigger a function in vim.  There is an autofunction that will
    trigger whenever the cursor moves, which is the next best thing.
    """
    global status, length_of_last_input_request
    if km is None:
        return False
    newprompt = False
    gotoend = False # this is a hack for moving to the end of the prompt when new input is requested that should get cleaned up

    msgs = km.sub_channel.get_msgs()
    msgs += km.stdin_channel.get_msgs() # also handle messages from stdin
    for m in msgs:
        if debugging:
            vib.append('message from ipython:')
            vib.append(repr(m).splitlines())
        if 'msg_type' not in m['header']:
            continue
        else:
            msg_type = m['header']['msg_type']
            
        s = None
        if msg_type == 'status':
            if m['content']['execution_state'] == 'idle':
                status = 'idle'
                newprompt = True
            else:
                newprompt = False
            if m['content']['execution_state'] == 'busy':
                status = 'busy'
            vim.command('let g:ipy_status="' + status + '"')
        elif msg_type == 'stream':
            s = strip_color_escapes(m['content']['data'])
            s = unh(s)
        elif msg_type == 'pyout':
            s = m['content']['data']['text/plain']
        elif msg_type == 'pyin':
            # don't want to print the input twice
            continue
        # TODO: add better error formatting
        elif msg_type == 'pyerr':
            c = m['content']
            s = vib_es
            s += "\n".join(map(strip_color_escapes,c['traceback']))
            s += vib_ee
            # s += c['ename'] + ": " + c['evalue']
        elif msg_type == 'object_info_reply':
            c = m['content']
            if not c['found']:
                s = c['name'] + " not found!"
            else:
            # TODO: finish implementing this
                s = unh(c['docstring'])
        elif msg_type == 'input_request':
            s = m['content']['prompt']
            status = 'input requested'
            vim.command('let g:ipy_status="' + status + '"')
            length_of_last_input_request = len(m['content']['prompt'])
            gotoend = True

        elif msg_type == 'crash':
            s = "The IPython Kernel Crashed!"
            s += "\nUnfortuneatly this means that all variables in the interactive namespace were lost."
            s += "\nHere is the crash info from IPython:\n"
            s += repr(m['content']['info'])
            s += "Type CTRL-F12 to restart the Kernel"
        
        if s: # then update the vipy buffer with the formatted text
            if s.find('\n') == -1: # then use ugly unicode workaround from 
                # http://vim.1045645.n5.nabble.com/Limitations-of-vim-python-interface-with-respect-to-character-encodings-td1223881.html
                if isinstance(s,unicode):
                    s = s.encode(vim_encoding)
                vib.append(s)
                if debugging:
                    vib.append('using unicode workaround')
            else:
                try:
                    vib.append(s.splitlines())
                except:
                    vib.append([l.encode(vim_encoding) for l in s.splitlines()])
        
    # move to the vipy (so that the autocommand can scroll down)
    if in_vipy():
        if newprompt:
            new_prompt()
        if gotoend:
            goto_vib()

        # turn off some mappings when input is requested (e.g. the history search)
        if status == "input requested" and vib_map == "on":
            enter_debug()
        if vib_map == "off" and status != "input requested":
            enter_normal()

    else:
        if newprompt:
            new_prompt(goto=False)
        if is_vim_ipython_open():
            goto_vib(insert_at_end=False)
            vim.command('exe "normal G\<C-w>p"')
    return len(msgs)

            
def get_child_msg(msg_id):
    while True:
        # get_msg will raise with Empty exception if no messages arrive in 5 second
        m= km.shell_channel.get_msg(timeout=5)
        if m['parent_header']['msg_id'] == msg_id:
            break
        else:
            #got a message, but not the one we were looking for
            if debugging:
                echo('skipping a message on shell_channel','WarningMsg')
    return m
            
def with_subchannel(f, *args, **kwargs):
    "conditionally monitor subchannel"
    def f_with_update(*args, **kwargs):
        try:
            f(*args, **kwargs)
            if monitor_subchannel:
                update_subchannel_msgs()
        except AttributeError: #if km is None
            echo("not connected to IPython", 'Error')
    return f_with_update

@with_subchannel
def run_this_file():
    msg_id = send("run %s %s" % (run_flags, repr(vim.current.buffer.name)[1:-1]))

@with_subchannel
def run_this_line():
    # don't send blank lines
    if vim.current.line != '':
        msg_id = send(vim.current.line.strip())

ws = re.compile(r'\s*')
@with_subchannel
def run_these_lines():
    vim.command('normal y')
    lines = vim.eval("getreg('0')").splitlines()
    ws_length = len(ws.match(lines[0]).group())
    lines = [line[ws_length:] for line in lines]
    msg_id = send("\n".join(lines))


# TODO: add support for nested cells
# TODO: fix glitch where the cursor moves incorrectly as a result of cell mode
# TODO: suppress the text output when in cell mode
cell_line = re.compile(r'^\s*##[^#]?')
@with_subchannel
def run_cell(progress=False):
    """ run the code between the previous ## and next ## """

    row, col = vim.current.window.cursor
    cb = vim.current.buffer
    nrows = len(cb)

    # find previous ## or start of file
    crow = row - 1
    cell_start = 0
    while crow > 0:
        if cell_line.search(cb[crow]):
            cell_start = crow
            break
        else:
            crow = crow - 1

    # find next ## or end of file
    crow = row
    cell_end = nrows
    while crow < nrows:
        if cell_line.search(cb[crow]):
            cell_end = crow
            break
        else:
            crow = crow + 1
    lines = cb[cell_start:cell_end]
    ws_length = len(ws.match(lines[0]).group())
    lines = [line[ws_length:] for line in lines]
    msg_id = send("\n".join(lines))

    if progress: # move cursor to next cell
        if cell_end >= nrows - 1:
            cell_end = nrows - 1
        vim.current.window.cursor = (cell_end + 1, 0)

## HELP BUFFER
try:
    vihb
except:
    vihb = None

def get_doc(word):
    msg_id = km.shell_channel.object_info(word)
    doc = get_doc_msg(msg_id)
    if len(doc) == 0:
        return ''
    else:
        # get around unicode problems when interfacing with vim
        return [d.encode(vim_encoding) for d in doc]

def get_doc_msg(msg_id):
    n = 13 # longest field name (empirically)
    b=[]
    try:
        content = get_child_msg(msg_id)['content']
    except Empty:
        # timeout occurred
        return ["no reply from IPython kernel"]

    if not content['found']:
        return b

    for field in ['type_name', 'base_class', 'string_form', 'namespace',
            'file', 'length', 'definition', 'source', 'docstring']:
        c = content.get(field, None)
        if c:
            if field in ['definition']:
                c = strip_color_escapes(c).rstrip()
            s = field.replace('_',' ').title() + ':'
            s = s.ljust(n)
            if c.find('\n')==-1:
                b.append(s + c)
            else:
                b.append(s)
                b.extend(c.splitlines())
    return b

def get_doc_buffer(level=0):
    global vihb
    if status == 'busy':
        echo("Can't query for Help When IPython is busy.  Do you have figures opened?")
        return
    if km is None:
        echo("Not connected to the IPython kernel... Type CTRL-F12 to start it.")

    # empty string in case vim.eval return None
    word = vim.eval('expand("<cfile>")') or ''
    doc = get_doc(word)
    if len(doc) == 0 :
        echo(repr(word) + " not found", "Error")
        # TODO: revert to normal K
        return
    doc[0] = vib_ns + doc[0]
    doc[-1] = doc[-1] + doc[-1]

    # see if the doc window has already been made, if not create it
    try:
        vihb
    except:
        vihb = None
    if not vihb:
        vim.command('new vipy-help.py')
        vihb = vim.current.buffer
        vim.command("setlocal nonumber")
        vim.command("setlocal bufhidden=hide buftype=nofile ft=python noswf nobl")
        vim.command("noremap <buffer> K <C-w>p")
        # doc window quick quit keys: 'q' and 'escape'
        vim.command('noremap <buffer> q :q<CR>')
        # Known issue: to enable the use of arrow keys inside the terminal when
        # viewing the documentation, comment out the next line
        vim.command('map <buffer> <Esc> :q<CR>')
        vim.command('setlocal nobl')
        vim.command('resize 20')
        setup_highlighting()

    # fill the window with the correct content
    vihb[:] = None
    vihb[:] = doc

## HELPER FUNCTIONS
def goto_vib(insert_at_end=True):
    global vib
    try:
        name = vib.name
        vim.command('drop ' + name)
        if insert_at_end:
            vim.command('normal G')
            vim.command('startinsert!')
    except:
        echo("""It appears that the vipy.py buffer was deleted.  You can create
        a new one without reseting the python server (and losing any variables
        in the interactive namespace) by running the command :python
        setup_vib(), or you can reset the server by pressing SHIFT-F12 to
        shutdown the server, and then CTRL-F12 to start it up again along with
        a new vipy buffer.""")
        vib = None

def toggle_vib():
    if in_vipy():
        if len(vim.windows) == 1:
            vim.command('bprevious')
        else:
            vim.command('exe "normal \<C-w>p"')
    else:
        goto_vib()

def at_end_of_prompt():
    """ Is the cursor at the end of a prompt line? """
    row, col = vim.current.window.cursor
    lineend = len(vim.current.line) - 1
    bufend = len(vim.current.buffer)
    return numspace.match(vim.current.line) and row == bufend and col == lineend

def above_prompt():
    """ See if the cursor is above the last >>> prompt. """
    row, col = vim.current.window.cursor
    i = len(vib) - 1
    last_prompt = 0
    while i >= 0:
        if vib[i].startswith(r'>>> '):
            last_prompt = i + 1 # convert from index to line-number
            break
    if row < last_prompt:
        return True
    else:
        return False

def unh(s):
    """ Use normal highlighting.

    Surround the text with syntax hints so that it uses the normal 
    highlighting.  This is accomplished using the vib_ns and vib_ne (normal
    start/end) strings. """ 
    if isinstance(s, list):
        if len(s) > 0:
            s[0] = vib_ns + s[0]
            s[-1] = s[-1] + vib_ne
    else: # if it is string
        if s == '':
            return ''
        if s[-1] == '\n':
            s = vib_ns + s[:-1] + vib_ne + '\n'
        else:
            s = vib_ns + s + vib_ne
    return s

def is_vim_ipython_open():
    """
    Helper function to let us know if the vipy shell is currently
    visible
    """
    for w in vim.windows:
        if w.buffer.name is not None and w.buffer.name.endswith("vipy.py"):
            return True
    return False

def in_vipy():
    cbn = vim.current.buffer.name
    if cbn:
        return cbn.endswith('vipy.py')
    else:
        return False

def insert_at_new():
    """ Insert at the bottom of the file, if it is the ipy buffer. """
    if in_vipy():
        # insert at end of last line
        vim.command('normal G')
        vim.command('startinsert!') 

def get_vim_ipython_buffer():
    """ Return the vipy buffer. """
    for b in vim.buffers:
        try:
            if b.name.endswith("vipy.py"):
                return b
        except:
            continue
    return False

def get_vim_ipython_window():
    """ Return the vipy window. """
    for w in vim.windows:
        if w.buffer.name is not None and w.buffer.name.endswith("vipy.py"):
            return w
    raise Exception("couldn't find vipy window")

def echo(arg,style="Question"):
    try:
        vim.command("echohl %s" % style)
        vim.command("echom \"%s\"" % arg.replace('\"','\\\"'))
        vim.command("echohl None")
    except vim.error:
        print "-- %s" % arg

# from http://serverfault.com/questions/71285/in-centos-4-4-how-can-i-strip-escape-sequences-from-a-text-file
strip = re.compile('\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]')
def strip_color_escapes(s):
    return strip.sub('',s)

indent_or_period = re.compile(r'[a-zA-Z0-9_.]')
EOF

" PYTHON FILE MAPPINGS
nnoremap <silent> <F5> :wa<CR>:py run_this_file()<CR><ESC>l
inoremap <silent> <F5> <ESC>:wa<CR>:py run_this_file()<CR>li
noremap <silent> K :py get_doc_buffer()<CR>
vnoremap <silent> <F9> y:py run_these_lines()<CR><ESC>
nnoremap <silent> <F9> :py run_this_line()<CR><ESC>j
noremap <silent> <F12> :py toggle_vib()<CR>
noremap <silent> <C-F12> :py startup()<CR>
noremap <silent> <S-F12> :py shutdown()<CR><ESC>
inoremap <silent> <F12> <ESC>:py toggle_vib()<CR>
inoremap <silent> <C-F12> <ESC>:py startup()<CR>
inoremap <silent> <S-F12> <ESC>:py shutdown()<CR>
inoremap <silent> <S-CR> <ESC>:set nohlsearch<CR>V?^\n<CR>:python run_these_lines()<CR>:let @/ = ""<CR>:set hlsearch<CR>Go<ESC>o

" CELL MODE MAPPINGS
nnoremap <silent> <S-CR> :py run_cell()<CR><ESC>
nnoremap <silent> <C-CR> :py run_cell(progress=True)<CR><ESC>
inoremap <silent> <S-CR> <ESC>:py run_cell()<CR><ESC>i
inoremap <silent> <C-CR> <ESC>:py run_cell(progress=True)<CR><ESC>i
vnoremap <silent> <S-CR> :py run_cell()<CR><ESC>gv
vnoremap <silent> <C-CR> :py run_cell(progress=True)<CR><ESC>gv


"finally
    "echoe 'unable to load vipy!  See https://github.com/johndgiese/vipy/issues for possible solutions.'
"endtry

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
    # get the object 
    oname = 'a'
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

    # request object info from ipython
    msg_id = km.shell_channel.object_info(oname,detail_level=1)

    try:
        m = get_child_msg(msg_id)
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

" Scrolling is nice when you are reading python documentation
function! LessMode()
  if g:vipy_lessmode == 0
    let g:vipy_lessmode = 1
    let onoff = 'on'
    " Scroll half a page down
    noremap <script> d <C-D>
    " Scroll one line down
    noremap <script> j <C-E>
    " Scroll half a page up
    noremap <script> u <C-U>
    " Scroll one line up
    noremap <script> k <C-Y>
  else
    let g:vipy_lessmode = 0
    let onoff = 'off'
    unmap d
    unmap j
    unmap u
    unmap k
  endif
  echohl Label | echo "Less mode" onoff | echohl None
endfunction
let g:vipy_lessmode = 0
