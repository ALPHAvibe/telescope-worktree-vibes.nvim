-- worktree-vibes.lua
-- Save this in ~/.config/nvim/lua/telescope/_extensions/worktree_vibes.lua

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local action_utils = require("telescope.actions.utils")
local entry_display = require("telescope.pickers.entry_display")

-- Config file path
local config_path = vim.fn.stdpath("data") .. "/worktree-vibes.json"

-- State for marked worktrees
local marked_worktrees = {}

-- Get git repository root
local function get_git_root()
  local result = vim.fn.systemlist("git rev-parse --show-toplevel")
  if vim.v.shell_error == 0 and #result > 0 then
    return result[1]
  end
  return nil
end

-- Load repo-specific config
local function load_config()
  local file = io.open(config_path, "r")
  if not file then
    return {}
  end
  local content = file:read("*a")
  file:close()

  local ok, config = pcall(vim.json.decode, content)
  if ok then
    return config
  end
  return {}
end

-- Save repo-specific config
local function save_config(config)
  local file = io.open(config_path, "w")
  if not file then
    vim.notify("Failed to save worktree-vibes config", vim.log.levels.ERROR)
    return
  end
  file:write(vim.json.encode(config))
  file:close()
end

-- Get default worktree path for current repo
local function get_default_path()
  local git_root = get_git_root()
  if not git_root then
    return nil
  end

  local config = load_config()
  return config[git_root]
end

-- Set default worktree path for current repo
local function set_default_path(path)
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end

  -- Expand tilde and ensure trailing slash
  local expanded_path = vim.fn.expand(path)
  if not expanded_path:match("/$") then
    expanded_path = expanded_path .. "/"
  end

  local config = load_config()
  config[git_root] = expanded_path
  save_config(config)
  vim.notify("Default worktree path set to: " .. expanded_path, vim.log.levels.INFO)
end

-- Get current working directory
local function get_current_dir()
  return vim.fn.getcwd()
end

-- Parse git worktree list
local function get_worktrees()
  local output = vim.fn.systemlist("git worktree list --porcelain")
  local worktrees = {}
  local current_wt = {}
  local current_dir = get_current_dir()

  for _, line in ipairs(output) do
    if line:match("^worktree ") then
      if current_wt.path then
        table.insert(worktrees, current_wt)
      end
      current_wt = {
        path = line:match("^worktree (.+)"),
        is_current = false,
        is_primary = false,
      }
    elseif line:match("^branch ") then
      current_wt.branch = line:match("^branch refs/heads/(.+)")
    elseif line:match("^HEAD ") then
      current_wt.head = line:match("^HEAD (.+)")
    elseif line:match("^bare") then
      current_wt.is_bare = true
    end
  end

  -- Add last worktree
  if current_wt.path then
    table.insert(worktrees, current_wt)
  end

  -- First worktree is always the primary/main worktree
  if #worktrees > 0 then
    worktrees[1].is_primary = true
  end

  -- Mark current worktree
  for _, wt in ipairs(worktrees) do
    if wt.path == current_dir then
      wt.is_current = true
    end
  end

  return worktrees
end

-- Get branches without worktrees (including remote branches)
local function get_available_branches()
  -- Get local branches
  local local_branches = vim.fn.systemlist("git branch --format='%(refname:short)'")

  -- Get remote branches
  local remote_branches = vim.fn.systemlist("git branch -r --format='%(refname:short)'")

  -- Get worktrees
  local worktrees = get_worktrees()
  local used_branches = {}

  -- Mark branches that already have worktrees
  for _, wt in ipairs(worktrees) do
    if wt.branch then
      used_branches[wt.branch] = true
    end
  end

  local available = {}

  -- Add local branches
  for _, branch in ipairs(local_branches) do
    if not used_branches[branch] then
      table.insert(available, { name = branch, is_remote = false })
    end
  end

  -- Add remote branches (skip HEAD and those with local counterparts)
  for _, branch in ipairs(remote_branches) do
    -- Skip HEAD pointer
    if not branch:match("HEAD") then
      -- Extract local name (e.g., origin/feature -> feature)
      local local_name = branch:match("^[^/]+/(.+)$")

      -- Only add if no local branch exists and no worktree exists
      if local_name and not used_branches[local_name] then
        local has_local = false
        for _, lb in ipairs(local_branches) do
          if lb == local_name then
            has_local = true
            break
          end
        end

        if not has_local then
          table.insert(available, { name = branch, local_name = local_name, is_remote = true })
        end
      end
    end
  end

  return available
end

-- Create new worktree picker
local function create_worktree_picker(opts, callback)
  opts = opts or {}
  local branches = get_available_branches()

  if #branches == 0 then
    vim.notify("No available branches without worktrees", vim.log.levels.WARN)
    return
  end

  pickers.new(opts, {
    prompt_title = "Create Worktree from Branch (Enter to select)",
    finder = finders.new_table({
      results = branches,
      entry_maker = function(entry)
        local display_name = entry.name
        local icon = entry.is_remote and "🌐 " or "📍 "

        return {
          value = entry,
          display = icon .. display_name,
          ordinal = display_name,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        local branch_info = selection.value
        local branch_name = branch_info.is_remote and branch_info.local_name or branch_info.name

        -- Use stored worktree path if set, otherwise default to ../branch
        local default_path
        local stored_path = get_default_path()
        if stored_path then
          -- stored_path already has trailing slash
          default_path = vim.fn.expand(stored_path) .. branch_name
        else
          default_path = "../" .. branch_name
        end

        vim.ui.input({
          prompt = "Worktree path: ",
          default = default_path,
        }, function(worktree_path)
          if worktree_path and worktree_path ~= "" then
            local cmd
            local result

            -- If it's a remote branch, create worktree with local branch tracking remote
            if branch_info.is_remote then
              vim.notify("Creating worktree from remote branch: " .. branch_info.name, vim.log.levels.INFO)
              cmd = string.format("git worktree add -b %s %s %s", branch_name, worktree_path, branch_info.name)
            else
              -- Local branch - standard worktree add
              cmd = string.format("git worktree add %s %s", worktree_path, branch_name)
            end

            result = vim.fn.system(cmd)

            if vim.v.shell_error == 0 then
              vim.notify("Created worktree: " .. worktree_path, vim.log.levels.INFO)
              -- Call callback to reopen main picker
              if callback then
                callback()
              end
            else
              vim.notify("Failed to create worktree: " .. result, vim.log.levels.ERROR)
              -- Still reopen picker on error
              if callback then
                callback()
              end
            end
          else
            -- User cancelled, reopen main picker
            if callback then
              callback()
            end
          end
        end)
      end)
      return true
    end,
  }):find()
end

-- Display format for worktree entries
local function make_display(entry)
  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },        -- emoji
      { remaining = true }, -- path
      { width = 35 },       -- branch
    },
  })

  local emoji = ""
  if entry.value.is_primary then
    emoji = "🏠"
  end
  if entry.value.is_current then
    emoji = emoji .. "💻"
  end
  if marked_worktrees[entry.value.path] then
    emoji = emoji .. "🗑️"
  end

  return displayer({
    emoji,
    { entry.value.path,                                   "TelescopeResultsIdentifier" },
    { entry.value.branch or entry.value.head or "[bare]", "TelescopeResultsComment" },
  })
end

-- Main worktree picker
local function worktree_picker(opts)
  opts = opts or {}
  local worktrees = get_worktrees()

  if #worktrees == 0 then
    vim.notify("No worktrees found", vim.log.levels.WARN)
    return
  end

  pickers.new(opts, {
    prompt_title = "Git Worktrees (Ctrl-c create | Ctrl-Shift-p set path | Ctrl-d mark | Ctrl-r delete)",
    finder = finders.new_table({
      results = worktrees,
      entry_maker = function(entry)
        return {
          value = entry,
          display = make_display,
          ordinal = entry.path .. " " .. (entry.branch or ""),
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      -- Default action: switch to worktree
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd("cd " .. selection.value.path)
        vim.notify("Switched to: " .. selection.value.path, vim.log.levels.INFO)
      end)

      -- Ctrl-c: Create new worktree
      map("i", "<C-c>", function()
        actions.close(prompt_bufnr)
        create_worktree_picker(opts, function()
          -- Reopen main picker after creation
          worktree_picker(opts)
        end)
      end)

      map("n", "<C-c>", function()
        actions.close(prompt_bufnr)
        create_worktree_picker(opts, function()
          -- Reopen main picker after creation
          worktree_picker(opts)
        end)
      end)

      -- Ctrl-Shift-p: Set default worktree path
      map("i", "<C-S-P>", function()
        actions.close(prompt_bufnr)

        local current_path = get_default_path() or ""
        vim.ui.input({
          prompt = "Default worktree path: ",
          default = current_path,
        }, function(path)
          if path and path ~= "" then
            set_default_path(path)
          end
          -- Reopen main picker
          worktree_picker(opts)
        end)
      end)

      map("n", "<C-S-P>", function()
        actions.close(prompt_bufnr)

        local current_path = get_default_path() or ""
        vim.ui.input({
          prompt = "Default worktree path: ",
          default = current_path,
        }, function(path)
          if path and path ~= "" then
            set_default_path(path)
          end
          -- Reopen main picker
          worktree_picker(opts)
        end)
      end)

      -- Ctrl-d: Mark for deletion
      map("i", "<C-d>", function()
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        local selections = current_picker:get_multi_selection()

        -- If no multi-selection, use current entry
        if vim.tbl_isempty(selections) then
          local selection = action_state.get_selected_entry()
          if selection then
            selections = { selection }
          end
        end

        -- Toggle mark for each selection
        for _, selection in ipairs(selections) do
          local path = selection.value.path
          if selection.value.is_primary then
            vim.notify("Cannot mark primary worktree for deletion", vim.log.levels.WARN)
          elseif selection.value.is_current then
            vim.notify("Cannot mark current worktree for deletion", vim.log.levels.WARN)
          else
            if marked_worktrees[path] then
              marked_worktrees[path] = nil
            else
              marked_worktrees[path] = true
            end
          end
        end

        -- Refresh picker to show marked items
        current_picker:refresh(finders.new_table({
          results = worktrees,
          entry_maker = function(entry)
            return {
              value = entry,
              display = make_display,
              ordinal = entry.path .. " " .. (entry.branch or ""),
            }
          end,
        }), { reset_prompt = false })
      end)

      map("n", "<C-d>", function()
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        local selections = current_picker:get_multi_selection()

        -- If no multi-selection, use current entry
        if vim.tbl_isempty(selections) then
          local selection = action_state.get_selected_entry()
          if selection then
            selections = { selection }
          end
        end

        -- Toggle mark for each selection
        for _, selection in ipairs(selections) do
          local path = selection.value.path
          if selection.value.is_primary then
            vim.notify("Cannot mark primary worktree for deletion", vim.log.levels.WARN)
          elseif selection.value.is_current then
            vim.notify("Cannot mark current worktree for deletion", vim.log.levels.WARN)
          else
            if marked_worktrees[path] then
              marked_worktrees[path] = nil
            else
              marked_worktrees[path] = true
            end
          end
        end

        -- Refresh picker
        current_picker:refresh(finders.new_table({
          results = worktrees,
          entry_maker = function(entry)
            return {
              value = entry,
              display = make_display,
              ordinal = entry.path .. " " .. (entry.branch or ""),
            }
          end,
        }), { reset_prompt = false })
      end)

      -- Ctrl-r: Delete marked worktrees
      map("i", "<C-r>", function()
        local to_delete = {}
        for path, _ in pairs(marked_worktrees) do
          table.insert(to_delete, path)
        end

        if #to_delete == 0 then
          vim.notify("No worktrees marked for deletion", vim.log.levels.WARN)
          return
        end

        local confirm = vim.fn.confirm(
          "Delete " .. #to_delete .. " worktree(s)?",
          "&Yes\n&No",
          2
        )

        if confirm == 1 then
          for _, path in ipairs(to_delete) do
            local cmd = string.format("git worktree remove %s", path)
            local result = vim.fn.system(cmd)
            if vim.v.shell_error == 0 then
              vim.notify("Removed: " .. path, vim.log.levels.INFO)
              marked_worktrees[path] = nil
            else
              vim.notify("Failed to remove " .. path .. ": " .. result, vim.log.levels.ERROR)
            end
          end

          -- Refresh picker
          worktrees = get_worktrees()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          current_picker:refresh(finders.new_table({
            results = worktrees,
            entry_maker = function(entry)
              return {
                value = entry,
                display = make_display,
                ordinal = entry.path .. " " .. (entry.branch or ""),
              }
            end,
          }), { reset_prompt = false })
        end
      end)

      map("n", "<C-r>", function()
        local to_delete = {}
        for path, _ in pairs(marked_worktrees) do
          table.insert(to_delete, path)
        end

        if #to_delete == 0 then
          vim.notify("No worktrees marked for deletion", vim.log.levels.WARN)
          return
        end

        local confirm = vim.fn.confirm(
          "Delete " .. #to_delete .. " worktree(s)?",
          "&Yes\n&No",
          2
        )

        if confirm == 1 then
          for _, path in ipairs(to_delete) do
            local cmd = string.format("git worktree remove %s", path)
            local result = vim.fn.system(cmd)
            if vim.v.shell_error == 0 then
              vim.notify("Removed: " .. path, vim.log.levels.INFO)
              marked_worktrees[path] = nil
            else
              vim.notify("Failed to remove " .. path .. ": " .. result, vim.log.levels.ERROR)
            end
          end

          -- Refresh picker
          worktrees = get_worktrees()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          current_picker:refresh(finders.new_table({
            results = worktrees,
            entry_maker = function(entry)
              return {
                value = entry,
                display = make_display,
                ordinal = entry.path .. " " .. (entry.branch or ""),
              }
            end,
          }), { reset_prompt = false })
        end
      end)

      return true
    end,
  }):find()
end

-- Telescope extension setup
return require("telescope").register_extension({
  exports = {
    worktree_vibes = worktree_picker,
  },
})
