-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Copy filename, line number and such
vim.keymap.set("n", "<leader>ypf", function()
  vim.fn.setreg(vim.v.register, vim.fn.expand("%:p"))
end, { desc = "Copy file path" })

vim.keymap.set("n", "<leader>ypl", function()
  vim.fn.setreg(vim.v.register, vim.fn.expand("%:p") .. ":" .. vim.fn.line("."))
end, { desc = "Copy file path and cursor line number" })

-- Claude Code
-- vim.keymap.set("n", "<leader>cc", "<cmd>ClaudeCode<CR>", { desc = "Toggle Claude Code" })
