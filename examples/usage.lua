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

				-- DAG checklist system configuration
				dag = {
					enabled = true,
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

-- DAG Checklist System Usage Examples
-- 
-- The DAG system provides a unified checklist tool for managing complex task workflows with dependencies.
-- The tool is available in CodeCompanion chat buffers as a function call.
--
-- Example 1: Create a checklist with dependencies
-- checklist({
--   action = "create",
--   goal = "Implement user authentication system",
--   tasks = {
--     { text = "Analyze existing auth patterns", mode = "read", dependencies = {} },
--     { text = "Review security requirements", mode = "read", dependencies = {} },
--     { text = "Design database schema", mode = "readwrite", dependencies = {1} },
--     { text = "Create unit tests", mode = "write", dependencies = {3} },
--     { text = "Implement authentication logic", mode = "write", dependencies = {1, 2, 3, 4} }
--   },
--   subject = "Auth system implementation",
--   body = "Complete authentication system with proper dependency management and parallel execution"
-- })
--
-- Example 2: List all checklists
-- checklist({ action = "list" })
--
-- Example 3: Check status of a specific checklist
-- checklist({ action = "status", checklist_id = "2" })
--
-- Example 4: Complete the current in-progress task
-- checklist({
--   action = "complete",
--   task_id = "1", 
--   subject = "Completed codebase analysis",
--   body = "Analyzed existing authentication patterns and identified key improvement areas"
-- })
--
-- Available Actions:
-- - create: Create a new checklist with tasks and dependencies
-- - list: List all existing checklists
-- - status: Get detailed status of a checklist  
-- - complete: Mark a task as complete
--
-- Key Features:
-- - Tasks with mode="read" and no dependencies execute in parallel automatically
-- - Dependencies are resolved using topological sorting
-- - Progress is tracked and persisted across sessions
-- - Visual indicators show task status: ✓ completed, ~ in progress, ! blocked
-- - Storage location: ~/.local/share/nvim/codecompanion-tools/dag_checklists.json
