-- Logger instance for Translator module
local logger_factory = require("codecompanion-tools.common.logger")
local cfg = require("codecompanion-tools.translator.config").opts

return logger_factory.create("translator", cfg.debug)
