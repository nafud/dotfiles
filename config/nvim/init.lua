-- Neovim, the workspace's editor: $EDITOR for git, yazi's `e` and the
-- shell (config/bash/profile), and the desktop's handler for text and
-- code (applications/nvim.desktop runs it inside alacritty; setup.sh
-- names it for the MIME types). No plugins — the stock editor, its
-- defaults changed only where the workspace differs.

-- The palette is the terminal's. Neovim switches truecolor on by
-- itself where the terminal offers it and then paints its own greys
-- over the glass; with it left off, the default colorscheme draws in
-- the sixteen ANSI colours, which alacritty maps onto
-- config/alacritty/mono.toml, and Normal carries no colour of its own,
-- so the terminal's glass shows through as it does under yazi and btop.
vim.o.termguicolors = false

-- four spaces, never a tab, except where the language insists: the
-- go and make filetype plugins keep tabs on their own
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4

vim.o.number = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.undofile = true

-- yank and put through the Wayland clipboard (wl-clipboard is in the
-- package set), the way zellij's copy_command already does
vim.o.clipboard = "unnamedplus"

-- writing a new file into a directory that does not exist yet makes
-- the directory rather than failing; only real files on disk, never a
-- special buffer or a remote path
vim.api.nvim_create_autocmd("BufWritePre", {
    callback = function(ev)
        if vim.bo[ev.buf].buftype ~= "" then return end
        local name = vim.api.nvim_buf_get_name(ev.buf)
        if name == "" or name:find("://", 1, true) then return end
        vim.fn.mkdir(vim.fs.dirname(name), "p")
    end,
})

-- reopen a file where it was left: the '" mark, as :help restore-cursor
-- spells it out, skipped for commit messages, rebase lists, hex dumps
-- and diffs, where the top is the place to start
vim.api.nvim_create_autocmd("BufReadPre", {
    callback = function(ev)
        vim.api.nvim_create_autocmd("FileType", {
            buffer = ev.buf,
            once = true,
            callback = function()
                local line = vim.fn.line([['"]])
                local ft = vim.bo.filetype
                if line >= 1 and line <= vim.fn.line("$")
                    and not ft:find("commit", 1, true)
                    and ft ~= "xxd" and ft ~= "gitrebase"
                    and not vim.wo.diff then
                    vim.cmd([[normal! g`"]])
                end
            end,
        })
    end,
})
