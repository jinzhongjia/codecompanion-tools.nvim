-- Usage example: How to configure codecompanion-tools in CodeCompanion

require("codecompanion").setup({
	-- Other CodeCompanion configuration...
	extensions = {
		-- Use extension name directly, no callback needed
		-- CodeCompanion will auto-find lua/codecompanion/_extensions/codecompanion-tools/init.lua
		["codecompanion-tools"] = {
			opts = {
				-- Rules manager configuration
				rules = {
					enabled = true,
					debug = false,
					rules_filenames = {
						".rules",
						".goosehints",
						".cursorrules",
						".windsurfrules",
						".clinerules",
						".github/copilot-instructions.md",
						"AGENT.md",
						"AGENTS.md",
						"CLAUDE.md",
						".codecompanionrules",
					},
					-- Custom file path extraction function (optional)
					extract_file_paths_from_chat_message = function(message)
						-- Extract file paths from message content
						-- Return array of paths
						return {}
					end,
				},

				-- Model toggle configuration
				model_toggle = {
					enabled = true,
					keymap = "<S-Tab>", -- Toggle shortcut

					-- Sequence mode: cross-adapter switching (recommended)
					sequence = {
						{ adapter = "copilot", model = "gpt-4.1" },
						{ adapter = "copilot", model = "o1-mini" },
						{ adapter = "anthropic", model = "claude-3-5-sonnet-20241022" },
						{ adapter = "openai", model = "gpt-4o" },
					},

					-- Or use models mode: same adapter, different models
					-- (models is ignored if sequence is set)
					-- models = {
					--   copilot = {
					--     "gpt-4.1",
					--     "o1-mini",
					--     "claude-3-5-sonnet-20241022",
					--   },
					--   anthropic = {
					--     "claude-3-5-sonnet-20241022",
					--     "claude-3-opus-20240229",
					--   },
					--   openai = {
					--     "gpt-4o",
					--     "gpt-4o-mini",
					--     "gpt-4-turbo",
					--   }
					-- }
				},
			},
		},
	},

	-- Other CodeCompanion configuration...
})

-- Manually call model toggle (optional)
-- vim.keymap.set("n", "<leader>tm", function()
--   require("codecompanion").extensions["codecompanion-tools"].toggle_model(vim.api.nvim_get_current_buf())
-- end, { desc = "Toggle model" })
