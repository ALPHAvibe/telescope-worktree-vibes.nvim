# telescope-worktree-vibes.nvim

A Telescope extension for managing git worktrees with ease and good vibes! 🎵

## Features

- 🔍 List and switch between git worktrees
- ➕ Create worktrees from local and remote branches
- 🗑️ Mark and batch delete worktrees
- 💾 Per-repository default worktree paths
- 🏠 Prevents deletion of primary worktree
- 💻 Visual indicators for current and primary worktrees
- 🌐 Support for remote branch checkout

## Requirements

- Neovim >= 0.9.0
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- Git with worktree support

## Installation

### lazy.nvim
```lua
{
  "ALPHAvibe/telescope-worktree-vibes.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("telescope").load_extension("worktree_vibes")
  end,
  keys = {
    { "<leader>gw", "<cmd>Telescope worktree_vibes<cr>", desc = "Worktree Vibes" },
  },
}
```

### packer.nvim
```lua
use {
  "ALPHAvibe/telescope-worktree-vibes.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("telescope").load_extension("worktree_vibes")
  end,
}
```

## Usage

Open the worktree picker with `:Telescope worktree_vibes` or your configured keybinding.

### Keybindings

In the worktree picker:
- **Enter** - Switch to selected worktree
- **Ctrl-c** - Create new worktree from branch
- **Ctrl-Shift-p** - Set default worktree path for current repo
- **Ctrl-r** - Mark/unmark worktree for deletion
- **Ctrl-d** - Delete all marked worktrees (with confirmation)

### Branch Indicators

When creating a worktree:
- 📍 - Local branch (already checked out)
- 🌐 - Remote branch (will be checked out and tracked)

### Worktree Indicators

- 🏠 - Primary/main worktree
- 💻 - Current active worktree
- 🗑️ - Marked for deletion

## Configuration

The plugin stores per-repository default paths in `~/.local/share/nvim/worktree-vibes.json`.

To set a default path for your repo:
1. Open the worktree picker
2. Press `Ctrl-p`
3. Enter your preferred path (e.g., `~/projects/worktrees/`)

All future worktrees will default to this location.

## Optional Enhancement

For a better input experience, install [dressing.nvim](https://github.com/stevearc/dressing.nvim):
```lua
{ "stevearc/dressing.nvim" }
```


