# Features
This plugin provides a special vim buffer that acts like the ipython terminal.  No more alt-tabbing from your editor to the interpreter!  This special buffer has the following features:
* Search command history from previous sessions using up and down arrows
* Vim's python highlighting in the terminal
* Appropriatly handles input and raw_input requests from IPython; this allows the use of the command line python debugger
* Smart autocomplete using IPython (also available in all other open python buffers)
* The status of the IPython kernel is displayed in the status line of the vipy buffer.

![demo](https://github.com/johndgiese/vipy/raw/master/demo.PNG)

# About
I am a graduate student who has used MATLAB for many years; eventually I became frustrated with its limitations and switched to python+numpy+scipy+matplotlib+ipython.  This combination provides a powerful environment for scientific computing, however I became frustrated having the editor and python interpreter in separate programs.  I found this to be a limitation for a number of reasons:
1. Alt-tabbing is annoying
2. You can't execute the selected text (e.g. F9 in MATLAB)
3. You don't have cell-mode (CTRL-ENTER in MATLAB)
4. No graphical debugger (pdb is painful to use)
5. Autocomplete is oblivious to the variables in the current session.
6. The syntax highlighting in IPython and Vim are different.
Vim is my favorite debugger, because it is SOOO much faster (after several frustrating weeks getting used to it) than other editors.  These complaints combined with my love for vim prompted me to look for some way to integrate vim and ipython together.
After searching for a while (and trying a number of dead-ends), I found [Ivanov's Vim-IPython](https://github.com/ivanov/vim-ipython).  His plugin is really great, and I very much appreciate all the work he put into it, however it wasn't quite what I had in mind, so I made a number of substantial modifications to it (rewriting the majority of the code underneath in the process).  I have added several features, and over the next few months will continue to add them until I have an editor environment that fits my needs.

I am still testing my code, so if you run into bugs please post them as a git issue.

I have only used it on gvim 7.3 (should work on vim 7.3) with IPython 0.14 and 0.15 on Windows 7, 64bit (should work on 32bit).

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