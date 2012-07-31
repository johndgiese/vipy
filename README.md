# Features
This plugin provides a special Vim buffer that acts like the IPython terminal.  No more alt-tabbing from your editor to the interpreter!  This special buffer has the following features:
* Search command history from previous sessions using up and down arrows
* Appropriately handles input and raw_input requests from IPython; this allows the use of the command line python debugger
* You can set your default IPython profile in your vimrc file (g:vipy_profile=myprofile)
* Consistent python syntax highlighting in the editor and the terminal 
* Convenience methods for editing files (e.g. pythonObject?? will open the file where the object is defined in a new vim buffer)

The plugin also provides a number of features for all python files:

* Smart autocomplete using IPython's object? ability
* Execute the current visual selection with F9
* Run the current file by pressing F5
* CTRL-ENTER and SHIFT-ENTER will run the current "cell" (i.e. like MATLAB's cell mode; see below for more details)

An example vipy session with one regular python file, and the special vipy buffer to the right:
![demo](https://github.com/johndgiese/vipy/raw/master/demo.PNG)

# About
I am a graduate student who has used MATLAB for many years; eventually I became frustrated with its limitations and switched to python+numpy+scipy+matplotlib+ipython.  This combination provides a powerful environment for scientific computing, however I missed having the editor and interpreter in the same program (like in MATLAB).  I found this to be a limitation for a number of reasons:

1. Alt-tabbing is slow and annoying
2. It is very useful to be able to select an expression, and execute it (e.g. F9 in MATLAB)
3. You can't have conveniences like cell-mode (CTRL-ENTER in MATLAB)
4. There is no graphical debugger (pdb is painful to use)
5. Autocomplete is oblivious to the variables in the current session
6. The syntax highlighting in IPython and Vim are different

Vim is my favorite editor, because it is so much faster (after several frustrating weeks getting used to it) than other editors, so I started looking for some way to integrate Vim and IPython together.
After searching for a while (and trying a number of dead-ends), I found [Ivanov's Vim-IPython](https://github.com/ivanov/vim-ipython).  His plugin is really great, and I very much appreciate all the work he put into it, however it wasn't quite what I had in mind, so I started tweaking it, and before long I had made a number of substantial modifications to it (rewriting the majority of the code underneath in the process).  I have added several features, and over the next few months will continue to add them until I have an editor environment that fits my needs.

I am still testing my code, so if you run into bugs please post them as a git issue.

I have only used it on gvim 7.3 (should work on vim 7.3) with IPython 0.14 and 0.15 on Windows 7, 64bit (should work on 32bit).

# Installation
* Install IPython 0.14 or 0.15
* Install pyzmq (so that vim can talk to the IPython server)
* Install vim with +python support (use :version to see if you have it)
* If you are using windows 64bit, fix the manifest as described [here](https://github.com/ivanov/vim-ipython/issues/20).
* Download vipy.vim and place it in the directory .vim/ftplugin/python/vipy.vim or if you are using pathogen, in bundle/vipy/ftplugin/python/vipy.vim

# Basic Usage
* Open a python file in vim
* Press CTRL-F12 to start vipy

CTRL-F12 will look for an opened IPython kernel, but if it can't find one it will start one for you in a separate command window (don't close it manually!).  After connecting to the IPython kernel, vipy will open a new vim window to the right of the current vim window with a special buffer loaded in it, called vipy.py.

The vipy buffer has some special mappings that make it act like the IPython prompt
* You can execute commands by pressing SHIFT-ENTER
* Press enter to create a new line with "... " so that you can execute multi-line inputs like for loops and if statements
* If you are in insert mode, and the cursor is at the end of the last line, then UP and DOWN will search the command history for all matches starting with the current line's content.  Pressing UP and DOWN repeatedly will loop through the matches; this works even for multi-line inputs such as for loops.  If the current line is an empty prompt, pressing up and down will loop through the last 50 inputs.  If the cursor is anywhere except the end of the buffer, the up and down arrows will act normally.
* F12 will goto the previously used window
* Typing object? will print the IPython help, properly formatted.
* Typing object?? will open the file where the object is defined in a vim buffer.
* The vipy buffer has special syntax highlighting; input is formatted as usual, while standard output (except for python documentation) uses normal formatting.  This is an advantage over the normal IPython console, because vim's colorschemes are not restricted to ascii colors, and the console highlighting will follow the same setup you have for your regular python files.
* The status of the IPython kernel is displayed in the status line of the vipy buffer

If you are in another python file (not the vipy buffer):
* CTRL-F5 will execute the current file
* F9 in visual mode will execute the selected text
* F9 in normal mode will execute the current line, and progress to the next line, so that you "step" through a simple file by pressing F9 repeatedly.
* Pressing K in normal mode will open the documentation for the word that the cursor is on, in a new window.  While in this documentation window, pressing K again will move the cursor back to the previous spot (while keeping the window open).  Pressing q or ESC from within the documentation buffer will close it.
* Pressing F12 will drop the vipy buffer in the current window if it isn't currently opened in any vim window, otherwise it will move the cursor to the end of the vipy buffer.
* SHIFT-F12 will wipe the vipy buffer and close the kernel
* SHIFT-ENTER will execute the current CELL.  For anyone who is unfamiliar with MATLAB's cell mode, it works as follows: A cell is a set of statements surrounded by a special comment starting with two pound signs (i.e. ##).  If you press SHIFT-ENTER the current cell will be executed.  If you press CTRL-ENTER, the current cell will be executed, and the cursor will progress to the next cell, so that you can conveniently step through cells of your program.  Cell mode is useful for situations where you want to load data once, but execute some analysis of that data multiple times

Note that the vipy buffer is designed to act similarly to the MATLAB command window/editor.  I.e. you will have your normal python files opened in various windows, and you will also have the vipy buffer (i.e. the command window) open in a separate window.  You can close the vipy window if you want, and the buffer will remain in the background.

The vipy.py buffer tries to be pretty smart about how it handles the prompts and output, however fundamentally it is normal vim buffer, and thus you can edit it how you would a normal buffer.  This is good and bad; you can use your favorite shortcuts, however you can also confuse it if you delete the prompts (i.e. the ">>> " of the "... " if you are entering a multiline command").

# Currently being worked on
* Graphical debugger
* Bug fixes
* Checking to see if it works on Mac and Linux

# Known issues:
* If CTRL-F12 doesn't work the first time, it is probably because IPython interpreter was manually shutdown last time; you can fix this by pressing SHIFT-F12 (to remove the old connection files), and then press CTRL-F12 to restart vipy
* Sometimes after executing a command in the vipy buffer, the cursor will leave insert mode.  I am trying to find a workaround for this.
* Messes up if you change the vim directory using :cd newdir.  I am working on fixing this.
