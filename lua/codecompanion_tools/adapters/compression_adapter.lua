local BaseAdapter = require("codecompanion_tools.adapters.base_adapter")
local compression_manager = require("codecompanion_tools.context_compression.compression_manager")

local CompressionAdapter = BaseAdapter:new("compression", {
	enabled = true,
	auto_compress = true,
	threshold = 8000,
	adapter = "copilot",
	model = "gpt-4.1",
	debug = false,
})

function CompressionAdapter:initialize()
	BaseAdapter.initialize(self)

	-- 初始化压缩管理器
	compression_manager.init(self.config)

	-- 创建工具
	self.tools = {
		compress_context = self:create_compress_tool(),
		compression_stats = self:create_stats_tool(),
		compression_recommend = self:create_recommend_tool(),
	}

	-- 创建命令
	self:setup_commands()

	-- 设置自动压缩
	if self.config.auto_compress then
		self:setup_auto_compression()
	end
end

function CompressionAdapter:create_compress_tool()
	return {
		name = "compress_context",
		description = "Compress chat context to reduce token usage",
		parameters = {
			type = "object",
			properties = {
				adapter = {
					type = "string",
					description = "Adapter to use for compression",
					default = self.config.adapter,
				},
				model = {
					type = "string",
					description = "Model to use for compression",
					default = self.config.model,
				},
				target_ratio = {
					type = "number",
					minimum = 0.1,
					maximum = 0.9,
					default = 0.6,
				},
			},
		},
		run = function(args)
			local chat_utils = require("codecompanion_tools.chat")
			local bufnr = vim.api.nvim_get_current_buf()
			local chat = chat_utils.get_chat(bufnr)

			if not chat then
				return "Error: No codecompanion chat found in current buffer"
			end

			local options = {
				adapter = args.adapter,
				model = args.model,
				target_ratio = args.target_ratio,
			}

			local success, error_msg, stats = compression_manager.compress_context(chat, options)

			if success then
				return string.format("Compression successful: %s", vim.json.encode(stats))
			else
				return string.format("Compression failed: %s", error_msg or "Unknown error")
			end
		end,
	}
end

function CompressionAdapter:create_stats_tool()
	return {
		name = "compression_stats",
		description = "Get compression statistics for current chat",
		parameters = {
			type = "object",
			properties = {},
		},
		run = function()
			local chat_utils = require("codecompanion_tools.chat")
			local bufnr = vim.api.nvim_get_current_buf()
			local chat = chat_utils.get_chat(bufnr)

			if not chat then
				return "Error: No codecompanion chat found in current buffer"
			end

			local stats = compression_manager.get_compression_stats(chat)
			return vim.json.encode(stats)
		end,
	}
end

function CompressionAdapter:create_recommend_tool()
	return {
		name = "compression_recommend",
		description = "Check if compression is recommended for current chat",
		parameters = {
			type = "object",
			properties = {},
		},
		run = function()
			local chat_utils = require("codecompanion_tools.chat")
			local bufnr = vim.api.nvim_get_current_buf()
			local chat = chat_utils.get_chat(bufnr)

			if not chat then
				return "Error: No codecompanion chat found in current buffer"
			end

			local recommended, urgency, reasons = compression_manager.is_compression_recommended(chat)

			return vim.json.encode({
				recommended = recommended,
				urgency = urgency,
				reasons = reasons,
			})
		end,
	}
end

function CompressionAdapter:setup_commands()
	local config_utils = require("codecompanion_tools.config")

	config_utils.setup_commands("CodeCompanionCompress", {
		Now = {
			callback = function()
				self.tools.compress_context.run({})
			end,
			desc = "Compress current chat context",
		},
		Stats = {
			callback = function()
				print(self.tools.compression_stats.run())
			end,
			desc = "Show compression statistics",
		},
		Toggle = {
			callback = function()
				self.config.auto_compress = not self.config.auto_compress
				print("Auto compression:", self.config.auto_compress)
				if self.config.auto_compress then
					self:setup_auto_compression()
				end
			end,
			desc = "Toggle auto compression",
		},
	})
end

function CompressionAdapter:setup_auto_compression()
	local config_utils = require("codecompanion_tools.config")
	local group = config_utils.create_augroup("CompressionAdapter")

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "CodeCompanionChatFinished",
		callback = function(args)
			if not self.config.auto_compress then
				return
			end

			local chat_utils = require("codecompanion_tools.chat")
			local chat = chat_utils.get_chat(args.buf)

			if chat then
				local recommended = compression_manager.is_compression_recommended(chat)
				if recommended then
					compression_manager.compress_context(chat)
				end
			end
		end,
	})
end

return CompressionAdapter
