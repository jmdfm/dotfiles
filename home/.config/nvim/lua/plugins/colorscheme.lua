-- One fixed colorscheme (this config is only used where Omarchy isn't).
return {
  {
    'rebelot/kanagawa.nvim',
    lazy = false,
    priority = 1000,
    config = function() vim.cmd.colorscheme('kanagawa') end,
  },
}
