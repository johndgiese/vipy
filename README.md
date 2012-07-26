# Features
* You don't need to use a separate editor and terminal when working with python (no more alt-tabbing)
* Search command history from previous sessions (uses IPython for this)
* Vim's python highlighting in the terminal
* Appropriatly handles input and raw_input requests from IPython; this allows the use of the command line python debugger
* Smart autocomplete using IPython
* The status of the IPython kernel is displayed in the status line of the vim-ipython buffer.
![demo](https://github.com/johndgiese/vipython/raw/master/demo.PNG)

# vipython

Vim plugin that allows you to use IPython within vim.
Based loosely off of [Ivanov's Vim-IPython](https://github.com/ivanov/vim-ipython).
I am still testing this and adding features, so if you run into bugs please post them as a git issue.
I have only tested this on gvim 7.3 (should work on vim 7.3) with IPython 0.14 and 0.15 on Windows 7, 64bit (should work on 32bit).

# Intstallation
* Install IPython 0.14 or 0.15
* Install pyzmq (so that vim can talk to the IPython server)
* If you are using windows 64bit, fix the manifest as described [here](https://github.com/ivanov/vim-ipython/issues/20).
* Download vipython.vim and place it in the directory .vim/ftplugin/python/vipython.vim or if you are using pathogen, in bundle/vipython/ftplugin/python/vipython.vim


# Basic Usage
* Open a python file in vim.
* Press CTRL-F12 to start vim-ipython.  

This will start an IPython kernel and open a new buffere called vim-ipython.py.  If the cursor bounces between the vim-ipython buffer and the previous window, you may have to press SHIFT-F12 (to close vipython) and press CTRL-F12 again to restart it. (see known issues)

Note that vipython is designed to act similarly to the MATLAB command window/editor.  I.e. you will have your normal python files opened in various windows, and you will also have the vim-ipython buffer (i.e. the command window) open in a separte window.  You can close the vim-ipython window if you want, and the buffer will remain in the background.

The vim-ipython buffer has some special mappings that make it act like a console:
* Execute commands by pressing SHIFT-ENTER after the ">>> " or "... "
* Press enter to create a new line without executing (e.g. for for loops)
* dd will delete the line and create a new prompt
* 0 will goto the begining of the prompt
* F12 will goto the previously used window
* Typing object? will print the IPython help, properly formatted.
* Typing object?? will open the file where the object is defined in a vim buffer.

If you are in another python file (not the vim-ipython buffer):
* CTRL-F5 will execute the current file
* F9 in visual mode will execute the selected text
* F9 in normal mode will execute the current line
* Pressing K in normal mode will open the documentation for the word that the cursor is on.
* Pressing F12 will drop the vim-ipython buffer in the current window if it isn't currently opened in any vim window, otherwise it will move the cursor to the end of the vim-ipython buffer.
* SHIFT-F12 will wipe the vim-ipython buffer and close the kernel

The vim-ipython.py buffer tries to be pretty smart about how it handles the prompts and output, however fundamentally it is norml vim buffer, and thus you can edit it how you would a normal buffer.  This is good and bad; you can use your favorite shortcuts, however you can also confuse it if you delete the prompts (i.e. the ">>> " of the "... " if you are entering a multiline command").

# Currently being worked on
* Graphical debugger
* Bug fixes
* Checking to see if it works on Mac and Linux

# Known issues:
* CTRL-F12 doesn't work the first time.  Close the IPython process command window that was opened by pressing CTRL-F12, and try again.
* Sometimes after executing a command in the vim-ipython buffer, the cursor will leave insert mode.  I am trying to find a workaround for this.
* Messes up if you change the vim directory using :cd newdir.  I am working on fixing this.