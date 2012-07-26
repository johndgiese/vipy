vipython
========

Vim plugin that allows you to use IPython within vim.

Based loosely off of [Ivanov's Vim-IPython](https://github.com/ivanov/vim-ipython).

I am still testing this and adding features, so if you run into bugs please post them as a git issue.

I have only tested this on gvim 7.3 (should work on vim 7.3) with IPython 0.14 and 0.15 on Windows 7, 64bit (should work on 32bit).

You will need to install pyzmq so that vim can talk to the IPython server.  There are some problems doing this on Windows 7 64bit (some .dll problem).  That being said, it is possible to get it working (I have on a couple different computers now).  See [here](https://github.com/ivanov/vim-ipython/issues/20).

# Basic Usage
* Open a python file in vim.
* Press CTRL-F12 to start vim-ipython.  This will start an IPython kernel and open a new buffere called vim-ipython.py.  You may have to do this twice (see known issues)

The vim-ipython buffer has some special mappings that make it act like a console:
* Execute commands by pressing SHIFT-ENTER after the ">>> " or "... "
* Press enter to create a new line without executing (e.g. for for loops)
* dd will delete the line and create a new prompt
* 0 will goto the begining of the prompt
* F12 will goto the previously used window
* Typing object?? will open the file where the object is defined in a vim buffer.

If you are in another python file (not the vim-ipython buffer):
* CTRL-F5 will execute the current file
* F9 in visual mode will execute the selected text
* F9 in normal mode will execute the current line
* Pressing K in normal mode will open the documentation for the word that the cursor is on.

The vim-ipython 

Features:
* Search command history from previous sessions (uses IPython for this)
* Vim's python highlighting in the terminal

Known issues:
* CTRL-F12 doesn't work the first time.  Close the IPython process command window that was opened by pressing CTRL-F12, and try again.
* Sometimes after executing a command in the vim-ipython buffer, the cursor will leave insert mode.  I am trying to find a workaround for this.