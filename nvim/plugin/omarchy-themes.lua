-- Dynamic Omarchy Theme Integration for Neovim
-- Automatically loads themes and plugins based on omarchy's current theme

local M = {}

-- Get the current omarchy theme name
function M.get_current_theme()
    local theme_path = vim.fn.expand("~/.config/omarchy/current/theme")
    
    -- Check if the symlink exists
    if vim.fn.isdirectory(theme_path) == 0 and vim.fn.filereadable(theme_path) == 0 then
        return nil
    end
    
    -- Use system readlink command since vim.fn.readlink doesn't exist in all versions
    local handle = io.popen("readlink '" .. theme_path .. "' 2>/dev/null")
    if not handle then
        return nil
    end
    
    local theme_link = handle:read("*a"):gsub("%s+$", "") -- trim whitespace
    handle:close()
    
    if theme_link == "" then
        return nil
    end
    
    return vim.fn.fnamemodify(theme_link, ":t")
end

-- Load and parse a theme's neovim.lua config
function M.load_theme_config(theme_name)
    local theme_config_path = vim.fn.expand("~/.config/omarchy/themes/" .. theme_name .. "/neovim.lua")
    
    if vim.fn.filereadable(theme_config_path) == 0 then
        return nil
    end
    
    -- Load the theme config file
    local ok, theme_config = pcall(dofile, theme_config_path)
    if not ok or not theme_config then
        vim.notify("Failed to load theme config for " .. theme_name, vim.log.levels.WARN)
        return nil
    end
    
    return theme_config
end

-- Extract plugins from theme config
function M.extract_plugins(theme_config)
    local plugins = {}
    
    for _, config in ipairs(theme_config) do
        -- Handle different plugin config formats
        if type(config) == "string" then
            -- Simple string format: "author/repo"
            table.insert(plugins, { src = "https://github.com/" .. config })
        elseif type(config) == "table" then
            if config[1] and type(config[1]) == "string" then
                -- Format: { "author/repo", ... }
                local repo = config[1]
                local plugin_config = { src = "https://github.com/" .. repo }
                
                -- Copy other properties (name, priority, etc.)
                for key, value in pairs(config) do
                    if key ~= 1 and key ~= "config" then
                        plugin_config[key] = value
                    end
                end
                
                table.insert(plugins, plugin_config)
            elseif config.src then
                -- Direct src format
                table.insert(plugins, config)
            end
        end
    end
    
    return plugins
end

-- Apply theme configuration (colorscheme, background, etc.)
function M.apply_theme_config(theme_config)
    for _, config in ipairs(theme_config) do
        if type(config) == "table" then
            -- Handle LazyVim-style opts
            if config.opts and config.opts.colorscheme then
                vim.schedule(function()
                    -- Wait a bit longer for plugins to be available
                    vim.defer_fn(function()
                        local ok, _ = pcall(vim.cmd.colorscheme, config.opts.colorscheme)
                        if not ok then
                            vim.notify("Colorscheme '" .. config.opts.colorscheme .. "' not found, keeping default", vim.log.levels.WARN)
                        end
                        if config.opts.background then
                            pcall(function()
                                vim.opt.background = config.opts.background
                            end)
                        end
                    end, 100) -- 100ms delay
                end)
            end
            
            -- Handle direct config functions
            if config.config and type(config.config) == "function" then
                vim.schedule(function()
                    vim.defer_fn(function()
                        pcall(config.config)
                    end, 100)
                end)
            end
        end
    end
end

-- Load theme plugins dynamically
function M.load_theme_plugins()
    local current_theme = M.get_current_theme()
    
    if not current_theme then
        vim.notify("No omarchy theme detected, using fallback", vim.log.levels.INFO)
        return {}
    end
    
    local theme_config = M.load_theme_config(current_theme)
    
    if not theme_config then
        vim.notify("No neovim config found for theme: " .. current_theme, vim.log.levels.INFO)
        return {}
    end
    
    local plugins = M.extract_plugins(theme_config)
    
    vim.notify("Loading theme: " .. current_theme .. " (" .. #plugins .. " plugins)", vim.log.levels.INFO)
    
    -- Apply theme configuration after Neovim is fully loaded
    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.schedule(function()
                M.apply_theme_config(theme_config)
            end)
        end,
        once = true,
    })
    
    return plugins
end

-- Command to reload theme
vim.api.nvim_create_user_command("ReloadTheme", function()
    local current_theme = M.get_current_theme()
    if current_theme then
        local theme_config = M.load_theme_config(current_theme)
        if theme_config then
            M.apply_theme_config(theme_config)
            vim.notify("Reloaded theme: " .. current_theme, vim.log.levels.INFO)
        end
    end
end, { desc = "Reload current omarchy theme" })

return M