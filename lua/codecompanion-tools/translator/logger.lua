-- Translator 模块的 logger 实例
local logger_factory = require("codecompanion-tools.common.logger")
local cfg = require("codecompanion-tools.translator.config").opts

return logger_factory.create("translator", cfg.debug)
