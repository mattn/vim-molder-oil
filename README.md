# vim-molder-oil

Oil-like file operations for [vim-molder](https://github.com/mattn/vim-molder/)

This plugin provides oil.nvim-inspired file operations for vim-molder, allowing you to edit file names and directories directly in the buffer like editing text.

## Features

- Rename files/directories by editing their names in the buffer
- Delete files/directories by removing lines
- Create new files/directories by adding lines
- Move files/directories by editing their paths
- Preview operations before execution with confirmation dialog
- Windows and Unix compatible

## Installation

For [vim-plug](https://github.com/junegunn/vim-plug) plugin manager:

```vim
Plug 'mattn/vim-molder'
Plug 'mattn/vim-molder-oil'
```

## Usage

1. Open a directory with vim-molder:
   ```
   $ vim /path/to/directory/
   ```

2. Edit the buffer like normal text:
   - **Rename**: Edit the filename on a line
   - **Delete**: Delete the line (`:d` or `dd`)
   - **Create file**: Add a new line with the filename
   - **Create directory**: Add a new line with the name ending in `/` or `\`
   - **Move**: Edit the path to include directory separators

3. Save the buffer (`:w`) to execute operations
   - A confirmation dialog will show all pending operations
   - Press `y` to confirm or `n` to cancel

## Example Operations

```
Before:           After (edit):      Operation:
------            --------------     ----------
file.txt          newname.txt        Rename file.txt → newname.txt
olddir/           newdir/            Rename directory
file.txt          (deleted line)     Delete file.txt
                  newfile.txt        Create newfile.txt
                  newdir/            Create directory newdir
file.txt          subdir/file.txt    Move file.txt to subdir/
```

## Requirements

- Vim with textprop support (Vim 8.1+)
- vim-molder

## License

MIT

## Author

Yasuhiro Matsumoto
