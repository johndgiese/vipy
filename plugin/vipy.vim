" Vim plugin for integrating IPython into vim for fast python programming
" Last Change: 2012 Aug
" Maintainer: J. David Giese <johndgiese@gmail.com>
" License: This file is placed in the public domain.

" TODO: make C-F12 work outside of python files
" TODO: add directory customization
" FIXME: error with normalstart when there is a single apastrophe between them
" FIXME: the color coding breaks sometimes when if 
" TODO: better documentation
"
" TODO: figure out what is wrong with ion()
" TODO: make vim-only commands work even if there are multiple entered
" togethre
" TODO: fix cursor issue
" TODO: better tab complete which can tell if you are in a function call, and return arguments as appropriatey)
" TODO: use the ipython color codes as syntax blocks in vib
" TODO: when there is really long output, and the user is in the vib, then
" make it act like less (so that you can scroll down)
" TODO: ipython won't close with S-F12 if figures are open; figure out why and
" fix
" FIXME: running a file with F5 places you in insert mode
" TODO: prevent F9 and other mappings from throwing warnings when python is
" not open
" FIXME: there is a bug that will occur if the vipy buffer isn't shown
" in any window, and you press F12 (I think it only occurs if you have
" changed the vim path using :cd new_directory) The bufexplorer doesn't work
" when this bug occurs
" TODO: handle copy-pasting into vib better
" TODO: figure out a way to tell if the kernel is closed...
" TODO: add debugger capabilites
"
" TODO: write the user guide, including advantages of vipy over other
" setups

if !has('python')
    " exit if python is not available.
    echoe('In order to use vipy you must have a version of vim or gvim that is compiled with python support.')
    finish
endif

" add this back when I am done developing
"if exists("g:loaded_vipy")
"   finish
"endif
"let g:loaded_vipy = 1

let g:ipy_status="idle"

" let the user specify the IPython profile they want to use
if !exists('g:vipy_profile')
    let g:vipy_profile='default'
endif

if !exists('g:vipy_position')
    let g:vipy_position='rightbelow'
endif

if !exists('g:vipy_clean_connect_files')
    let g:vipy_clean_connect_files=1
endif

function! g:vipySyntax()
    syn region VipyIn start=/\v(^\>{3})\zs/ end=/\v\ze^.{0,2}$|\ze^\>{3}|\ze^[^.>]..|\ze^.[^.>].|\ze^..[^.>]/ contains=ALL transparent keepend
    syn region VipyOut start=/\v\zs^.{0,2}$|\zs^[^.>]..|\zs^.[^.>].|\zs^..[^.>]/ end=/\v\ze^\>{3}/ 
    hi link VipyOut Normal
endfunction






























" just for development: the line numbers in errors are now offset by 100
python << EOF
import vim
import sys
import re
import os
from os.path import basename
try:
    import IPython
    version = IPython.__version__.split('.')
    if float(version[0]) == 0 and float(version[1]) < 13:
        vim.command("echoe('vipy requires IPython >= 0.13, you have ipython version" + IPython.__version__ + "')")
        raise ImportErorr('vipy requires IPython >= 0.13')
except:
    # let vim's try-catch handle this             
    raise

try:
    from IPython.zmq.blockingkernelmanager import BlockingKernelManager, Empty
    from IPython.lib.kernel import find_connection_file
except ImportError:
    vim.command("echoe('You must have pyzmq >= 2.1.4 installed so that vim can communicate with IPython.')")
    if vim.eval("has('win64')") == '1':
        vim.command("echoe('There is a known issue with pyzmq on 64 bit windows machines.')")
    raise

debugging = False
in_debugger = False
monitor_subchannel = True   # update vipy 'shell' on every send?
run_flags= "-i"             # flags to for IPython's run magic when using <F5>
current_line = ''

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
    global km, fullpath, km_started_by_vim, profile_dir
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
        profile_dir = vim.eval('system("ipython locate profile ' + profile + '")').strip()
        if not os.path.exists(profile_dir):
            echo("It doesn't appear that the IPython profile, %s, specified using the g:vipy_profile variable exists.  Creating the profile ..." % profile)
            external_in_bg('ipython profile create ' + profile)
            profile_dir = vim.eval('system("ipython locate profile ' + profile + '")').strip()

        fullpath = None
        try:
            # see if there is already an IPython instance open ...
            fullpath = find_connection_file('', profile=profile)

            # TODO: figure out a cleaner way
            # if clean_connect_files option is selected remove connection files, and raise an error to get into the except block
            if vim.eval('g:vipy_clean_connect_files'):
                connect_dir = os.path.dirname(fullpath)
                connect_files = [p for p in os.listdir(connect_dir) if p.endswith('.json')]
                for p in connect_files:
                    os.remove(os.path.join(connect_dir, p))
                fullpath = None
                raise Exception
        except: # ... if not start one
            ipy_args = '--profile=' + profile

            external_in_bg('ipython kernel ' + ipy_args)
                
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
            return

        vib = get_vim_ipython_buffer()
        if not vib:
            setup_vib()
        else:
            echo('It appears that there is already a file named vipy.py open! This will cause errors unless it is generated by the vipy plugin (i.e. if it is a regular file named vipy.py).')
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
        if km != None:
            try:
                km.shell_channel.shutdown()
                km.cleanup_connection_file()
            except:
                echo('The kernel must have already shut down.')
        else:
            echo('The kernel must have already shut down.')


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
    try:
        vim.command("au! vimipython")
    except:
        pass

def km_from_connection_file():
    return

def setup_vib():
    """ Setup vib (vipy buffer), that acts like a prompt. """
    global vib
    vipy_pos = vim.eval('g:vipy_position')
    vim.command(vipy_pos + " new vipy.py")
    # set the global variable for everyone to reference easily
    vib = get_vim_ipython_buffer()
    if not vib:
        echo('It appears that your value for g:vipy_position is invalid!  See :help vipy')
    new_prompt(append=False)

    vim.command("setlocal nonumber")
    vim.command("setlocal bufhidden=hide buftype=nofile ft=python noswf")
    # turn of auto indent (there is some custom indenting that accounts
    # for the prompt).  See vim-tip 330
    vim.command("setl noai nocin nosi inde=") 
    vim.command("syn match Normal /^>>>/")

    # mappings to control sending stuff from vipy
    vim.command('inoremap <expr> <buffer> <silent> <s-cr> pumvisible() ? "\<ESC>:py print_completions()\<CR>" : "\<ESC>:py shift_enter_at_prompt()\<CR>"')
    vim.command('nnoremap <buffer> <silent> <cr> <ESC>:py enter_at_prompt()<CR>')
    vim.command('inoremap <buffer> <silent> <cr> <ESC>:py enter_at_prompt()<CR>')

    # setup history mappings etc.
    enter_normal(first=True)

    # add and auto command, so that the cursor always moves to the end
    # upon entereing the vipy buffer
    vim.command("au WinEnter <buffer> :python insert_at_new()")
    # not working; the idea was to make
    # vim.command("au InsertEnter <buffer> :py if above_prompt(): vim.command('normal G$')")
    vim.command("setlocal statusline=\ VIPY:\ %-{g:ipy_status}")
    
    # handle syntax coloring a little better
    vim.command('call g:vipySyntax()') # avoid problems with \v being escaped in the regexps

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

def enter_debug():
    """ Remove all the convenience mappings. """
    global vib_map, in_debugger
    vib_map = "off"
    in_debugger = True
    #    try:
    #        vim.command("iunmap <buffer> <silent> <up>")
    #        vim.command("iunmap <buffer> <silent> <down>")
    #        vim.command("iunmap <buffer> <silent> <right>")
    #        vim.command("nunmap <buffer> <silent> dd")
    #        vim.command("nunmap <buffer> <silent> <home>")
    #        vim.command("iunmap <buffer> <silent> <home>")
    #        vim.command("nunmap <buffer> <silent> 0")
    #    except vim.error:
    #        pass


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

def if_vipy_started(func):
    def wrapper(*args, **kwargs):
        if km:
            func(*args, **kwargs)
        else:
            echo("You must start VIPY first, using <CTRL-F5>")
    return wrapper
            
def db_check(func):
    """ Check whether in debug mode and print prompt. """
    def wrapper(*args, **kwargs):
        global in_debugger
        if in_debugger:
            prompt = func(*args, **kwargs)
        else:
            echo("This key only works in debug mode")

    return wrapper

@if_vipy_started
@db_check
def db_step():
    km.stdin_channel.input('n')
    return 'next'

@if_vipy_started
@db_check
def db_stepinto():
    km.stdin_channel.input('s')
    return 'step'

@if_vipy_started
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

@if_vipy_started
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
def shift_enter_at_prompt():
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
        vim.command('call feedkeys("\<CR>", "n")')

from math import ceil
def print_completions(invipy=True):
    """ Print the current completions into the vib buffer.

    This helps when there are a lot of completions, or you want
    to use them as a reference. """
    # grab current input
    if len(completions) > 2:
        # TODO: make this work on multi-line input
        # Save the original input
        del completions[0]
        input_length = 1
        input = vib[-input_length:]
        
        # format the text from the list of completions
        vib_width = vim.current.window.width
        max_comp_len = max([len(c) for c in completions]) + 1 # 1 is for the space
        num_col = int(vib_width/max_comp_len)
        if num_col == 0:
            num_col = 1
        comp_per_col = int(ceil(len(completions)/float(num_col)))
        
        # a list of lists of strings on each line
        formatted = [] # the formatted lines
        on_line = [completions[i::comp_per_col] for i in xrange(comp_per_col)] 
        for line in on_line:
            tmp = ''
            for comp in line:
                tmp += comp.ljust(max_comp_len)
            formatted.append(tmp)

        # append the completions
        if len(vib) == 1:
            vib[0] = formatted[0]
        else:
            vib[-1] = formatted[0]
        if len(formatted) > 1:
            vib.append(formatted[1:])

        # then append the old input and scroll to the bottom
        vib.append(input)
        goto_vib()
        if not invipy:
            toggle_vib()


def enter_at_prompt():
    """ Remove prompts and whitespace before sending to ipython. """
    if status == 'input requested':
        km.stdin_channel.input(vib[-1][length_of_last_input_request:])
    else:
        stop_str = r'>>>'
        cmds = []
        linen = len(vib)
        while linen > 0:
            # remove the last three characters
            cmd = vib[linen - 1]
            # only add the line if it isn't empty
            if len(cmd) > 4:
                cmds.append(cmd[4:]) 

            if cmd.startswith(stop_str):
                break
            else:
                linen -= 1
        if len(cmds) == 0:
            return
        cmds.reverse()


        cmds = '\n'.join(cmds)
        if cmds == 'cls' or cmds == 'clear':
            vib[:] = None # clear the buffer
            new_prompt(append=False)
        elif cmds.startswith('edit ') or cmds.startswith('vedit ') or cmds.startswith('sedit '):
            fnames = cmds[5:].split(' ')
            for fname in fnames:
                try:
                    pwd = get_ipy_pwd()
                    pp = os.path.join(pwd, fname)
                    if cmds[0] == 'e':
                        vim.command('edit ' + pp)
                    elif cmds[0] == 'v':
                        vim.command('vsp ' + pp)
                    else: # ... if cmds[0] == 's':
                        vim.command('sp ' + pp)
                except:
                    vib.append("Couldn't find " + pp)
        elif cmds.strip() == 'cdv':
            try:
                pwd = get_ipy_pwd()
                vim.command('cd ' + pwd)
            except:
                vib.append("Couldn't change vim cwd to %s" % cmds.strip())
        elif cmds.endswith('??'):
            obj = cmds[:-2]
            msg_id = km.shell_channel.object_info(obj)
            try:
                content = get_child_msg(msg_id)['content']
            except Empty:
                # timeout occurred
                return echo("no reply from IPython kernel")
            deffind = False
            if content['found']:
                if content['file']:
                    vim.command("drop " + content['file'])
                    vim.command("set syntax=python")

                    # try to position the cursor in the source file
                    #                    if content['source']:
                    #                        firstNL = content['source'].find('\n')
                    #                        if firstNL != -1:
                    #                            firstLine = content['source'][:firstNL]
                    #                        else:
                    #                            firstLine = content['source']
                    #                        cursorPositioner = re.compile(firstLine)
                    # if content['definition']:
                    #    cursorPositioner = re.compile(content['definition'])
                    if content['type_name'] == 'function':
                        deffind = re.compile('def ' + obj.split('.')[-1] + '[ (]')
                    elif content['type_name'] == 'classobj':
                        deffind = re.compile('class ' + obj.split('.')[-1] + '[ (]')
                    else:
                        deffind = re.compile(obj.split('.')[-1] + '[ (]')


                    if deffind:
                        for ind, line in enumerate(vim.current.buffer):
                            if deffind.match(line):
                                vib.append('match found at %d' % ind)
                                break

                    content = None
                else:
                    content = "IPython could not find a source file associated with %s." % obj
            else:
                content = "IPython could not find no object information associated with %s. \
                    Make sure that the requested object is in the interactive namespace and \
                    try again." % obj
            if content:
                vib.append(content)
            new_prompt()
            
            # this is ugly to put the cursor movement here: TODO: find a better way
            if deffind and deffind.match(line):
                vim.current.window.cursor = (ind + 1, 0)
            else:
                vim.current.window.cursor = (1, 0)


        elif cmds.endswith('?'):
            content = get_doc(cmds[:-1])
            if content == '':
                content =  'No matches found for: %s' % cmds[:-1]
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
        elif msg_type == 'pyout':
            s = m['content']['data']['text/plain']
        elif msg_type == 'pyin':
            # don't want to print the input twice
            continue
        # TODO: add better error formatting
        elif msg_type == 'pyerr':
            c = m['content']
            s = "\n".join(map(strip_color_escapes, c['traceback']))
        elif msg_type == 'object_info_reply':
            c = m['content']
            if not c['found']:
                s = c['name'] + " not found!"
            else:
            # TODO: finish implementing this
                s = c['docstring']
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

@if_vipy_started
@with_subchannel
def run_this_file():
    fname = repr(vim.current.buffer.name) # use repr to avoid escapes
    fname = fname.rstrip('ru') # remove r or u if it is raw or unicode
    fname = fname[1:-1] # remove the quotations
    fname = fname.replace('\\\\','\\')
    msg_id = send("run %s %s" % (run_flags, fname))

@if_vipy_started
@with_subchannel
def run_this_line():
    # don't send blank lines
    if vim.current.line != '':
        msg_id = send(vim.current.line.strip())

ws = re.compile(r'\s*')
@if_vipy_started
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
@if_vipy_started
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

def print_help():
    word = vim.eval('expand("<cfile>")') or ''
    doc = get_doc(word)
    if len(doc) == 0 :
        vib.append(doc)

## HELPER FUNCTIONS

def external_in_bg(cmd):
    """ Run an external command, either minimized if on windows, or in the
    background if on a unix system. """
    if vim.eval("has('win32')") == '1' or vim.eval("has('win64')") == '1':
        vim.command('!start /min ' + cmd)
    elif vim.eval("has('unix')") == '1' or vim.eval("has('mac')") == '1':
        vim.command('!' + cmd + ' &')

ds2ss = re.compile(r'\\\\')
def get_ipy_pwd():
    msg_id = km.shell_channel.execute('', user_expressions={'pwd': 'get_ipython().magic("pwd")'})
    try:
        pwd = get_child_msg(msg_id)
        pwd = pwd['content']['user_expressions']['pwd'][2:-1] # remove the u'....'
        pwd = re.sub(ds2ss, r'/', pwd)
        return pwd
    except Empty:
        # timeout occurred
        return echo("no reply from IPython kernel")

def goto_vib(insert_at_end=True):
    global vib
    try:
        name = get_vim_ipython_buffer().name
        vim.command('drop ' + name)
        if insert_at_end:
            vim.command('normal G')
            vim.command('startinsert!')
    except:
        echo("It appears that the vipy.py buffer was deleted.  If the ipython kernel is still open, you can create a new vipy buffer without reseting the python server by pressing CTRL-F12.  If the ipython server is no longer available, reset the server by pressing SHIFT-F12 and then CTRL-F12 to start it up again along with a new vipy buffer.")
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

EOF

noremap <silent> <C-F12> :py startup()<CR>
noremap <silent> <S-F12> :py shutdown()<CR><ESC>
inoremap <silent> <C-F12> <ESC>:py startup()<CR>
inoremap <silent> <S-F12> <ESC>:py shutdown()<CR>

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
