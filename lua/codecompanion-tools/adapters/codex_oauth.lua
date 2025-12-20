-- Codex (ChatGPT) OAuth adapter for CodeCompanion
-- Provides OAuth 2.0 + PKCE authentication for OpenAI Codex API

local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local adapter_utils = require("codecompanion.utils.adapters")
local tool_utils = require("codecompanion.utils.tool_transformers")
local oauth_utils = require("codecompanion-tools.adapters.oauth_utils")

local M = {}

-- ============================================================================
-- Module-level token cache
-- ============================================================================
local _access_token = nil
local _refresh_token = nil
local _token_expires = nil
local _account_id = nil
local _token_loaded = false
local _response_id = nil

-- ============================================================================
-- OAuth Configuration
-- ============================================================================
local OAUTH_CONFIG = {
  CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann",
  REDIRECT_URI = "http://localhost:1455/auth/callback",
  AUTH_URL = "https://auth.openai.com/oauth/authorize",
  TOKEN_URL = "https://auth.openai.com/oauth/token",
  SCOPES = "openid profile email offline_access",
  CALLBACK_PORT = 1455,
  ACCESS_TOKEN_EXPIRY_BUFFER_MS = 60 * 1000,
  TOKEN_FILE = "codex_oauth.json",
}

-- ============================================================================
-- Codex API Configuration
-- ============================================================================
local CODEX_CONFIG = {
  ENDPOINT = "https://chatgpt.com/backend-api/codex/responses",
  HEADERS = {
    ["OpenAI-Beta"] = "responses=experimental",
    ["originator"] = "codex_cli_rs",
  },
  JWT_CLAIM_PATH = "https://api.openai.com/auth",
}

-- ============================================================================
-- Tool Bridge Prompt (from opencode-openai-codex-auth)
-- Tells Codex how to use CodeCompanion's tools
-- ============================================================================
local TOOL_BRIDGE_PROMPT = [[IMPORTANT: You are NOT in Codex CLI. Ignore any Codex CLI tool references (apply_patch, shell, etc.). Use ONLY the tools provided in the function schemas.]]

-- ============================================================================
-- Model Mapping (from opencode-openai-codex-auth/lib/request/helpers/model-map.ts)
-- Maps config model IDs to normalized API model names
-- ============================================================================
local MODEL_MAP = {
  ["gpt-5.2"] = "gpt-5.2",
  ["gpt-5.2-codex"] = "gpt-5.2-codex",

  ["gpt-5.1-codex"] = "gpt-5.1-codex",

  -- GPT-5.1 Codex Max Models
  ["gpt-5.1-codex-max"] = "gpt-5.1-codex-max",

  -- GPT-5.1 Codex Mini Models
  ["gpt-5.1-codex-mini"] = "gpt-5.1-codex-mini",

  -- GPT-5.1 General Purpose Models
  ["gpt-5.1"] = "gpt-5.1",

  -- Legacy Models (map to newer versions)
  ["gpt-5-codex"] = "gpt-5.1-codex",
  ["codex-mini-latest"] = "gpt-5.1-codex-mini",
  ["gpt-5"] = "gpt-5.1",
}

---Get normalized model name from config ID
---@param model_id string
---@return string
local function normalize_model(model_id)
  if not model_id then
    return "gpt-5.1-codex"
  end

  -- Direct lookup
  if MODEL_MAP[model_id] then
    return MODEL_MAP[model_id]
  end

  -- Case-insensitive lookup
  local lower_id = model_id:lower()
  for key, value in pairs(MODEL_MAP) do
    if key:lower() == lower_id then
      return value
    end
  end

  -- Default fallback
  return "gpt-5.1-codex"
end

-- ============================================================================
-- Model Family Detection & Reasoning Configuration
-- (from opencode-openai-codex-auth/lib/request/request-transformer.ts)
-- ============================================================================

---Determine model family for reasoning configuration
---@param model string
---@return string
local function get_model_family(model)
  local normalized = model:lower()

  if normalized:match("gpt%-5%.2%-codex") then
    return "gpt-5.2-codex"
  elseif normalized:match("gpt%-5%.2") then
    return "gpt-5.2"
  elseif normalized:match("codex%-max") then
    return "codex-max"
  elseif normalized:match("codex%-mini") or normalized == "codex-mini-latest" then
    return "codex-mini"
  elseif normalized:match("codex") then
    return "codex"
  else
    return "gpt-5.1"
  end
end

---Get reasoning effort choices based on model
---@param model string
---@return table
local function get_effort_choices(model)
  local family = get_model_family(model)

  if family == "codex-mini" then
    return { "medium", "high" }
  elseif family == "gpt-5.2" or family == "gpt-5.2-codex" or family == "codex-max" then
    return { "none", "low", "medium", "high", "xhigh" }
  elseif family == "gpt-5.1" then
    -- GPT-5.1 general purpose supports none
    return { "none", "low", "medium", "high" }
  else
    -- Codex models
    return { "low", "medium", "high" }
  end
end

---Get default reasoning effort based on model family
---@param model string
---@return string
local function get_default_effort(model)
  local family = get_model_family(model)

  if family == "codex-mini" then
    return "medium"
  elseif family == "gpt-5.2" or family == "gpt-5.2-codex" or family == "codex-max" then
    return "high"
  else
    return "medium"
  end
end

---Validate and normalize reasoning effort for the model
---@param model string
---@param effort string|nil
---@return string
local function validate_reasoning_effort(model, effort)
  local family = get_model_family(model)
  local valid_choices = get_effort_choices(model)

  -- Default if not provided
  if not effort then
    return get_default_effort(model)
  end

  -- Check if effort is valid for this model
  for _, choice in ipairs(valid_choices) do
    if effort == choice then
      return effort
    end
  end

  -- Fallback adjustments
  if family == "codex-mini" then
    if effort == "low" or effort == "none" then
      return "medium"
    elseif effort == "xhigh" then
      return "high"
    end
  elseif family == "codex" then
    if effort == "none" then
      return "low"
    elseif effort == "xhigh" then
      return "high"
    end
  elseif family ~= "gpt-5.2" and family ~= "gpt-5.2-codex" and family ~= "codex-max" then
    if effort == "xhigh" then
      return "high"
    end
  end

  return get_default_effort(model)
end

-- ============================================================================
-- Success HTML for OAuth callback
-- ============================================================================
local SUCCESS_HTML = [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Codex OAuth - CodeCompanion</title>
    <style>
        :root { color-scheme: light dark; }
        body {
            margin: 0; min-height: 100vh;
            display: flex; align-items: center; justify-content: center;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #f7f7f8; color: #202123;
        }
        main {
            width: min(448px, calc(100% - 3rem));
            background: #ffffff; border-radius: 16px;
            padding: 2.5rem 2.75rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { margin: 0 0 0.75rem; font-size: 1.75rem; font-weight: 600; }
        p { margin: 0 0 1.75rem; font-size: 1.05rem; line-height: 1.6; color: #6e6e80; }
        .action {
            display: inline-flex; padding: 0.65rem 1.85rem;
            border-radius: 8px; background: #10a37f; color: #fff;
            font-weight: 500; text-decoration: none;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #202123; color: #ececf1; }
            main { background: #343541; }
            p { color: #c5c5d2; }
        }
    </style>
</head>
<body>
    <main>
        <h1>Authentication Successful!</h1>
        <p>Your ChatGPT account is now linked to CodeCompanion. You can close this window and return to Neovim.</p>
        <a class="action" href="javascript:window.close()">Close window</a>
    </main>
</body>
</html>]]

-- ============================================================================
-- Token Management Functions
-- ============================================================================

---Extract ChatGPT account ID from JWT token
---@param token string
---@return string|nil
local function extract_account_id(token)
  local payload = oauth_utils.decode_jwt(token)
  if not payload then
    return nil
  end
  local auth_claim = payload[CODEX_CONFIG.JWT_CLAIM_PATH]
  if auth_claim and auth_claim.chatgpt_account_id then
    return auth_claim.chatgpt_account_id
  end
  return nil
end

---Get OAuth token file path
---@return string|nil
local function get_token_file_path()
  return oauth_utils.get_token_file_path(OAUTH_CONFIG.TOKEN_FILE)
end

---Load tokens from file
---@return boolean
local function load_tokens()
  if _token_loaded then
    return _access_token ~= nil and _refresh_token ~= nil
  end

  _token_loaded = true

  local token_file = get_token_file_path()
  if not token_file then
    return false
  end

  local data = oauth_utils.load_json_file(token_file)
  if data then
    _access_token = data.access_token
    _refresh_token = data.refresh_token
    _token_expires = data.expires
    _account_id = data.account_id
    return _refresh_token ~= nil
  end

  return false
end

---Save tokens to file
---@param access_token string
---@param refresh_token string
---@param expires number
---@param account_id string|nil
---@return boolean
local function save_tokens(access_token, refresh_token, expires, account_id)
  if not refresh_token or refresh_token == "" then
    log:error("Codex OAuth: Cannot save without refresh token")
    return false
  end

  local token_file = get_token_file_path()
  if not token_file then
    return false
  end

  local data = {
    access_token = access_token,
    refresh_token = refresh_token,
    expires = expires,
    account_id = account_id,
    created_at = os.time(),
    version = 1,
  }

  if oauth_utils.save_json_file(token_file, data) then
    _access_token = access_token
    _refresh_token = refresh_token
    _token_expires = expires
    _account_id = account_id
    _token_loaded = true
    log:info("Codex OAuth: Tokens saved successfully")
    return true
  end

  log:error("Codex OAuth: Failed to save tokens")
  return false
end

---Refresh access token using refresh token
---@return string|nil
local function refresh_access_token()
  if not _refresh_token or _refresh_token == "" then
    log:error("Codex OAuth: No refresh token available")
    return nil
  end

  log:debug("Codex OAuth: Refreshing access token")

  local response = curl.post(OAUTH_CONFIG.TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = "grant_type=refresh_token"
      .. "&refresh_token="
      .. oauth_utils.url_encode(_refresh_token)
      .. "&client_id="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID),
    timeout = 30000,
    on_error = function(err)
      log:error("Codex OAuth: Token refresh error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Codex OAuth: No response from token refresh request")
    return nil
  end

  if response.status >= 400 then
    log:error("Codex OAuth: Token refresh failed, status %d: %s", response.status, response.body or "no body")
    return nil
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data or not token_data.access_token then
    log:error("Codex OAuth: Invalid token refresh response")
    return nil
  end

  local expires = os.time() * 1000 + (token_data.expires_in or 3600) * 1000
  local new_refresh = token_data.refresh_token or _refresh_token
  local account_id = extract_account_id(token_data.access_token) or _account_id

  if save_tokens(token_data.access_token, new_refresh, expires, account_id) then
    log:debug("Codex OAuth: Access token refreshed successfully")
    return token_data.access_token
  end

  return nil
end

---Exchange authorization code for tokens
---@param code string
---@param verifier string
---@return boolean
local function exchange_code_for_tokens(code, verifier)
  if not code or code == "" or not verifier or verifier == "" then
    log:error("Codex OAuth: Authorization code and verifier required")
    return false
  end

  log:debug("Codex OAuth: Exchanging authorization code for tokens")

  local response = curl.post(OAUTH_CONFIG.TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = "grant_type=authorization_code"
      .. "&client_id="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID)
      .. "&code="
      .. oauth_utils.url_encode(code)
      .. "&code_verifier="
      .. oauth_utils.url_encode(verifier)
      .. "&redirect_uri="
      .. oauth_utils.url_encode(OAUTH_CONFIG.REDIRECT_URI),
    timeout = 30000,
    on_error = function(err)
      log:error("Codex OAuth: Token exchange error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Codex OAuth: No response from token exchange request")
    return false
  end

  if response.status >= 400 then
    log:error("Codex OAuth: Token exchange failed, status %d: %s", response.status, response.body or "no body")
    return false
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data then
    log:error("Codex OAuth: Invalid token exchange response")
    return false
  end

  if not token_data.access_token or not token_data.refresh_token then
    log:error("Codex OAuth: Missing tokens in response")
    return false
  end

  local expires = os.time() * 1000 + (token_data.expires_in or 3600) * 1000
  local account_id = extract_account_id(token_data.access_token)

  if not account_id then
    log:warn("Codex OAuth: Could not extract account ID from token")
  end

  return save_tokens(token_data.access_token, token_data.refresh_token, expires, account_id)
end

---Generate OAuth authorization URL
---@return { url: string, verifier: string, state: string }|nil
local function generate_auth_url()
  local pkce = oauth_utils.generate_pkce(64)
  if not pkce then
    return nil
  end

  local state = oauth_utils.generate_state()

  local query_params = {
    "response_type=code",
    "client_id=" .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID),
    "redirect_uri=" .. oauth_utils.url_encode(OAUTH_CONFIG.REDIRECT_URI),
    "scope=" .. oauth_utils.url_encode(OAUTH_CONFIG.SCOPES),
    "code_challenge=" .. oauth_utils.url_encode(pkce.challenge),
    "code_challenge_method=S256",
    "state=" .. oauth_utils.url_encode(state),
    "id_token_add_organizations=true",
    "codex_cli_simplified_flow=true",
    "originator=codex_cli_rs",
  }

  local auth_url = OAUTH_CONFIG.AUTH_URL .. "?" .. table.concat(query_params, "&")

  return {
    url = auth_url,
    verifier = pkce.verifier,
    state = state,
  }
end

---Get access token (from cache, file, or refresh)
---@return string|nil, string|nil
local function get_access_token()
  if not _token_loaded then
    load_tokens()
  end

  if _access_token and not oauth_utils.is_token_expired(_token_expires, OAUTH_CONFIG.ACCESS_TOKEN_EXPIRY_BUFFER_MS) then
    return _access_token, _account_id
  end

  if _refresh_token then
    local new_token = refresh_access_token()
    if new_token then
      return new_token, _account_id
    end
  end

  log:error("Codex OAuth: Access token not available. Please run :CCTools adapter codex auth")
  return nil, nil
end

-- ============================================================================
-- OAuth Setup Functions (exported for unified command)
-- ============================================================================

---Setup OAuth authentication (interactive)
---@return boolean
local function setup_oauth()
  local auth_data = generate_auth_url()
  if not auth_data then
    vim.notify("Unable to generate Codex OAuth authorization URL, please check logs.", vim.log.levels.ERROR)
    return false
  end

  vim.notify("Starting Codex OAuth authentication...", vim.log.levels.INFO)

  oauth_utils.start_oauth_server(OAUTH_CONFIG.CALLBACK_PORT, "/auth/callback", nil, SUCCESS_HTML, function(code, err, state)
    if err then
      vim.notify("Codex OAuth failed: " .. err, vim.log.levels.ERROR)
      return
    end

    if code then
      if state and state ~= auth_data.state then
        vim.notify("Codex OAuth failed: State mismatch - possible CSRF attack", vim.log.levels.ERROR)
        return
      end

      vim.notify("Authorization code received, exchanging for tokens...", vim.log.levels.INFO)
      if exchange_code_for_tokens(code, auth_data.verifier) then
        vim.notify("Codex OAuth authentication successful!", vim.log.levels.INFO)
      else
        vim.notify("Codex OAuth: Failed to exchange code for tokens", vim.log.levels.ERROR)
      end
    end
  end)

  local success = oauth_utils.open_url(auth_data.url)
  if not success then
    vim.notify("Unable to automatically open browser. Please manually open this URL:\n" .. auth_data.url, vim.log.levels.WARN)
  end

  return true
end

function M.setup_oauth()
  setup_oauth()
end

function M.show_status()
  load_tokens()
  if not _refresh_token then
    vim.notify("Codex OAuth: Not authenticated. Run :CCTools adapter codex auth", vim.log.levels.WARN)
    return
  end

  local status = "Codex OAuth: Authenticated"
  if _account_id then
    status = status .. " (Account: " .. _account_id:sub(1, 8) .. "...)"
  end
  if _access_token and not oauth_utils.is_token_expired(_token_expires, OAUTH_CONFIG.ACCESS_TOKEN_EXPIRY_BUFFER_MS) then
    status = status .. " - Token is valid"
  else
    status = status .. " - Token needs refresh"
  end
  vim.notify(status, vim.log.levels.INFO)
end

function M.clear_tokens()
  local token_file = get_token_file_path()
  if token_file and vim.fn.filereadable(token_file) == 1 then
    local success = pcall(vim.fn.delete, token_file)
    if success then
      _access_token = nil
      _refresh_token = nil
      _token_expires = nil
      _account_id = nil
      _token_loaded = false
      vim.notify("Codex OAuth: Tokens cleared.", vim.log.levels.INFO)
    else
      vim.notify("Codex OAuth: Failed to clear token file.", vim.log.levels.ERROR)
    end
  else
    vim.notify("Codex OAuth: No tokens to clear.", vim.log.levels.WARN)
  end
end

local INSTRUCTIONS_CACHE_FILE = "codex_instructions_cache.json"

local function get_instructions_cache_path()
  return oauth_utils.get_token_file_path(INSTRUCTIONS_CACHE_FILE)
end

local function load_cached_instructions()
  local cache_path = get_instructions_cache_path()
  if not cache_path then
    return nil
  end
  local data = oauth_utils.load_json_file(cache_path)
  if data and data.instructions and data.instructions ~= "" then
    return data.instructions
  end
  return nil
end

local function get_instructions()
  local cached = load_cached_instructions()
  if cached then
    return cached
  end
  local codex_instructions = require("codecompanion-tools.adapters.codex_instructions")
  return codex_instructions.INSTRUCTIONS
end

function M.update_instructions()
  local codex_instructions = require("codecompanion-tools.adapters.codex_instructions")

  vim.notify("Codex: Fetching latest instructions from GitHub...", vim.log.levels.INFO)

  local response = curl.get(codex_instructions.SOURCE_URL, {
    timeout = 15000,
    on_error = function(err)
      vim.notify("Codex: Failed to fetch instructions: " .. vim.inspect(err), vim.log.levels.ERROR)
    end,
  })

  if not response or response.status ~= 200 or not response.body or response.body == "" then
    vim.notify("Codex: Failed to fetch instructions from GitHub", vim.log.levels.ERROR)
    return
  end

  local cache_path = get_instructions_cache_path()
  if not cache_path then
    vim.notify("Codex: Unable to determine cache path", vim.log.levels.ERROR)
    return
  end

  local cache_data = {
    instructions = response.body,
    source_url = codex_instructions.SOURCE_URL,
    updated_at = os.date("%Y-%m-%d %H:%M:%S"),
    version = 1,
  }

  if oauth_utils.save_json_file(cache_path, cache_data) then
    vim.notify("Codex: Instructions updated successfully!", vim.log.levels.INFO)
  else
    vim.notify("Codex: Failed to save instructions cache", vim.log.levels.ERROR)
  end
end

-- ============================================================================
-- Adapter Creation
-- ============================================================================

---Create the adapter
---@return table
function M.create_adapter()
  return {
    name = "codex_oauth",
    formatted_name = "Codex (ChatGPT OAuth)",
    roles = {
      llm = "assistant",
      user = "user",
      tool = "tool",
    },
    opts = {
      stream = true,
      tools = true,
      vision = true,
    },
    features = {
      text = true,
      tokens = true,
    },
    url = CODEX_CONFIG.ENDPOINT,
    env = {
      api_key = function()
        local token, _ = get_access_token()
        return token
      end,
    },
    parameters = {
      store = false,
    },
    headers = {
      ["Authorization"] = "Bearer ${api_key}",
      ["Content-Type"] = "application/json",
      ["Accept"] = "text/event-stream",
      ["OpenAI-Beta"] = CODEX_CONFIG.HEADERS["OpenAI-Beta"],
      ["originator"] = CODEX_CONFIG.HEADERS["originator"],
    },

    handlers = {
      -- ========================================================================
      -- Lifecycle Handlers
      -- ========================================================================
      lifecycle = {
        ---@param self CodeCompanion.HTTPAdapter
        ---@return boolean
        setup = function(self)
          local access_token, account_id = get_access_token()
          if not access_token then
            vim.notify("Codex OAuth: Not authenticated. Run :CCTools adapter codex auth", vim.log.levels.ERROR)
            return false
          end

          self._account_id = account_id

          if account_id then
            self.headers["chatgpt-account-id"] = account_id
          end

          -- Set stream parameter
          if self.opts and self.opts.stream then
            self.parameters.stream = true
          end

          return true
        end,

        ---@param self CodeCompanion.HTTPAdapter
        ---@param data? table
        on_exit = function(self, data)
          _response_id = nil

          if data and data.status and data.status >= 400 then
            local error_msg = "Codex API error"
            local body = data.body or ""
            local headers = data.headers or {}
            local rate_limit_info = {}

            for _, header in ipairs(headers) do
              if header:match("x%-codex%-primary%-used%-percent") then
                rate_limit_info.used_percent = header:match(": (.+)$")
              elseif header:match("x%-codex%-primary%-reset%-at") then
                rate_limit_info.reset_at = header:match(": (.+)$")
              elseif header:match("x%-codex%-primary%-window%-minutes") then
                rate_limit_info.window_minutes = header:match(": (.+)$")
              end
            end

            local ok, json = pcall(vim.json.decode, body)
            if ok and json and json.error then
              local err_type = json.error.code or json.error.type or ""
              local err_message = json.error.message or ""

              if err_type == "usage_limit_reached" or err_type == "rate_limit_exceeded" then
                if rate_limit_info.window_minutes then
                  error_msg = string.format(
                    "ChatGPT usage limit reached. Try again in ~%s minutes.",
                    rate_limit_info.window_minutes
                  )
                else
                  error_msg = "ChatGPT usage limit reached. Please try again later."
                end
              elseif err_type == "usage_not_included" then
                error_msg = "This model is not included in your ChatGPT plan."
              else
                error_msg = err_message ~= "" and err_message or error_msg
              end
            end

            log:error("Codex OAuth: %s (status %d)", error_msg, data.status)
          end
        end,
      },

      -- ========================================================================
      -- Request Handlers
      -- ========================================================================
      request = {
        ---Build request parameters
        ---@param self CodeCompanion.HTTPAdapter
        ---@param params table
        ---@param messages table
        ---@return table
        build_parameters = function(self, params, messages)
          local model = self.schema.model.default
          if type(model) == "function" then
            model = model(self)
          end

          -- Normalize model name for API
          params.model = normalize_model(model)

          -- Get and validate reasoning effort
          local effort = params["reasoning.effort"] or params.reasoning and params.reasoning.effort
          effort = validate_reasoning_effort(model, effort)

          local default_summary = (effort == "high" or effort == "xhigh") and "detailed" or "auto"
          local summary = params["reasoning.summary"] or params.reasoning and params.reasoning.summary or default_summary

          -- Set reasoning configuration
          params.reasoning = {
            effort = effort,
            summary = summary,
          }

          -- Include encrypted reasoning content for stateless mode
          params.include = { "reasoning.encrypted_content" }

          -- Set text verbosity
          params.text = params.text or {}
          params.text.verbosity = params.text.verbosity or "medium"

          -- Set instructions (from cache or bundled default)
          params.instructions = get_instructions()

          -- Clean up nested parameters that were flattened
          params["reasoning.effort"] = nil
          params["reasoning.summary"] = nil

          return params
        end,

        ---Build messages for Codex Responses API
        ---@param self CodeCompanion.HTTPAdapter
        ---@param messages table
        ---@return table
        build_messages = function(self, messages)
          -- Separate system messages for instructions
          local system_instructions = {}
          for _, msg in ipairs(messages) do
            if msg.role == "system" then
              table.insert(system_instructions, msg.content)
            end
          end

          local input = {}
          local i = 1
          while i <= #messages do
            local msg = messages[i]

            if msg.role ~= "system" then
              -- Handle reasoning from previous responses
              if msg.reasoning then
                local reasoning_item = { type = "reasoning" }
                if msg.reasoning.content then
                  reasoning_item.summary = { { type = "summary_text", text = msg.reasoning.content } }
                end
                if msg.reasoning.encrypted_content then
                  reasoning_item.encrypted_content = msg.reasoning.encrypted_content
                end
                table.insert(input, reasoning_item)
              end

              -- Handle image messages
              if msg._meta and msg._meta.tag == "image" and msg.context and msg.context.mimetype then
                if self.opts and self.opts.vision then
                  local next_msg = messages[i + 1]
                  local combined_content = {
                    { type = "input_image", image_url = string.format("data:%s;base64,%s", msg.context.mimetype, msg.content) },
                  }
                  if next_msg and next_msg.role == msg.role and type(next_msg.content) == "string" then
                    table.insert(combined_content, { type = "input_text", text = next_msg.content })
                    i = i + 1
                  end
                  table.insert(input, { role = msg.role, content = combined_content })
                end
              -- Handle tool responses
              elseif msg.role == "tool" then
                table.insert(input, {
                  type = "function_call_output",
                  call_id = msg.tools and msg.tools.call_id or nil,
                  output = msg.content,
                })
              -- Handle tool calls from assistant
              elseif msg.tools and msg.tools.calls then
                local tool_calls = vim
                  .iter(msg.tools.calls)
                  :map(function(tool_call)
                    return {
                      type = "function_call",
                      id = tool_call.id,
                      call_id = tool_call.call_id,
                      name = tool_call["function"].name,
                      arguments = tool_call["function"].arguments,
                    }
                  end)
                  :totable()

                for _, tool_call in ipairs(tool_calls) do
                  table.insert(input, tool_call)
                end
              -- Handle regular text messages
              elseif type(msg.content) == "string" then
                table.insert(input, { role = msg.role, content = msg.content })
              elseif type(msg.content) == "table" then
                local content = {}
                for _, part in ipairs(msg.content) do
                  if part.type == "text" then
                    table.insert(content, { type = "input_text", text = part.text })
                  elseif part.type == "image_url" then
                    local url = part.image_url and part.image_url.url
                    if url then
                      table.insert(content, { type = "input_image", image_url = url })
                    end
                  end
                end
                if #content > 0 then
                  table.insert(input, { role = msg.role, content = content })
                end
              end
            end

            i = i + 1
          end

          if self.opts.tools then
            table.insert(system_instructions, TOOL_BRIDGE_PROMPT)
          end

          if #system_instructions > 0 then
            local developer_message = {
              type = "message",
              role = "developer",
              content = {
                {
                  type = "input_text",
                  text = table.concat(system_instructions, "\n"),
                },
              },
            }
            table.insert(input, 1, developer_message)
          end

          return { input = input }
        end,

        ---Build tools schema for the LLM
        ---@param self CodeCompanion.HTTPAdapter
        ---@param tools table<string, table>
        ---@return table|nil
        build_tools = function(self, tools)
          if not self.opts.tools or not tools then
            return
          end
          if vim.tbl_count(tools) == 0 then
            return
          end

          local transformed = {}
          for _, tool in pairs(tools) do
            for _, schema in pairs(tool) do
              if schema._meta and schema._meta.adapter_tool then
                if self.available_tools and self.available_tools[schema.name] then
                  self.available_tools[schema.name].callback(self, transformed)
                end
              else
                table.insert(
                  transformed,
                  tool_utils.transform_schema_if_needed(schema, {
                    strict_mode = true,
                  })
                )
              end
            end
          end

          return { tools = transformed }
        end,

        ---Build reasoning output for storage
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table
        ---@return nil|table
        build_reasoning = function(self, data)
          local reasoning = {}

          reasoning.content = vim
            .iter(data)
            :map(function(item)
              return item.content
            end)
            :filter(function(content)
              return content ~= nil
            end)
            :join("")

          vim.iter(data):each(function(item)
            if item.id then
              reasoning.id = item.id
            end
            if item.encrypted_content then
              reasoning.encrypted_content = item.encrypted_content
            end
          end)

          if vim.tbl_count(reasoning) == 0 then
            return nil
          end

          return reasoning
        end,
      },

      -- ========================================================================
      -- Response Handlers
      -- ========================================================================
      response = {
        ---Parse chat output from streaming response
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data string|table
        ---@param tools? table
        ---@return table|nil
        parse_chat = function(self, data, tools)
          if not data or data == "" then
            return nil
          end

          local data_mod = type(data) == "table" and data.body or adapter_utils.clean_streamed_data(data)
          local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })
          if not ok then
            return nil
          end

          -- Handle non-streamed response
          if not self.opts.stream then
            local reasoning = {}
            if json.output then
              for _, item in ipairs(json.output) do
                if item.type == "reasoning" then
                  reasoning.id = item.id
                  reasoning.encrypted_content = item.encrypted_content
                  for _, block in ipairs(item.summary or {}) do
                    if block.type == "summary_text" then
                      reasoning.content = reasoning.content and (reasoning.content .. "\n\n" .. block.text) or block.text
                    end
                  end
                end
              end
            end

            if json.output and tools then
              vim
                .iter(json.output)
                :filter(function(item)
                  return item.type == "function_call"
                end)
                :each(function(tool)
                  table.insert(tools, {
                    id = tool.id,
                    call_id = tool.call_id,
                    type = "function",
                    ["function"] = {
                      name = tool.name,
                      arguments = tool.arguments or "",
                    },
                  })
                end)
            end

            local content = json.output
                and json.output[1]
                and json.output[1].content
                and json.output[1].content[1]
                and json.output[1].content[1].text
              or nil

            return {
              status = "success",
              output = {
                role = self.roles.llm,
                reasoning = vim.tbl_count(reasoning) > 0 and reasoning or nil,
                content = content,
              },
            }
          end

          -- Handle streaming response
          if json.type == "response.created" then
            _response_id = json.response and json.response.id
          end

          local output = {}

          if json.type == "response.reasoning_summary_text.delta" then
            output = {
              role = self.roles.llm,
              reasoning = { content = json.delta or "" },
              meta = { response_id = _response_id },
            }
          elseif json.type == "response.output_text.delta" then
            output = {
              role = self.roles.llm,
              content = json.delta or "",
              meta = { response_id = _response_id },
            }
          elseif json.type == "response.completed" then
            if json.response and json.response.output then
              local reasoning = {}
              vim
                .iter(json.response.output)
                :filter(function(item)
                  return item.type == "reasoning"
                end)
                :each(function(item)
                  reasoning.id = item.id
                  reasoning.encrypted_content = item.encrypted_content
                end)

              if tools then
                vim
                  .iter(json.response.output)
                  :filter(function(item)
                    return item.type == "function_call" and item.status == "completed"
                  end)
                  :each(function(tool)
                    table.insert(tools, {
                      id = tool.id,
                      call_id = tool.call_id,
                      type = "function",
                      ["function"] = {
                        name = tool.name,
                        arguments = tool.arguments or "",
                      },
                    })
                  end)
              end

              output = {
                role = self.roles.llm,
                reasoning = vim.tbl_count(reasoning) > 0 and reasoning or nil,
                meta = { response_id = _response_id },
              }
            end
          end

          if vim.tbl_count(output) == 0 then
            return nil
          end

          return {
            status = "success",
            output = output,
          }
        end,

        ---Parse token count from response
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table
        ---@return number|nil
        parse_tokens = function(self, data)
          if data and data ~= "" then
            local data_mod = adapter_utils.clean_streamed_data(data)
            local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

            if ok then
              if json.type == "response.completed" and json.response and json.response.usage then
                return json.response.usage.total_tokens
              end
            end
          end
        end,
      },

      -- ========================================================================
      -- Tools Handlers
      -- ========================================================================
      tools = {
        ---Format tool calls for inclusion in request
        ---@param self CodeCompanion.HTTPAdapter
        ---@param tools table
        ---@return table
        format_calls = function(self, tools)
          return tools
        end,

        ---Format tool response for inclusion in messages
        ---@param self CodeCompanion.HTTPAdapter
        ---@param tool_call table
        ---@param output string
        ---@return table
        format_response = function(self, tool_call, output)
          return {
            role = self.roles.tool or "tool",
            tools = {
              id = tool_call.id,
              call_id = tool_call.call_id,
            },
            content = output,
            opts = { visible = false },
          }
        end,
      },
    },

    -- ========================================================================
    -- Schema Definition
    -- ========================================================================
    schema = {
      model = {
        order = 1,
        mapping = "parameters",
        type = "enum",
        desc = "The model that will complete your prompt.",
        default = "gpt-5.1-codex",
        choices = {
          ["gpt-5.2"] = {
            formatted_name = "GPT-5.2",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
          ["gpt-5.2-codex"] = {
            formatted_name = "GPT-5.2 Codex",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
          ["gpt-5.1-codex-max"] = {
            formatted_name = "GPT-5.1 Codex Max",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
          ["gpt-5.1-codex"] = {
            formatted_name = "GPT-5.1 Codex",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
          ["gpt-5.1-codex-mini"] = {
            formatted_name = "GPT-5.1 Codex Mini",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
          ["gpt-5.1"] = {
            formatted_name = "GPT-5.1",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
          ["codex-mini-latest"] = {
            formatted_name = "Codex Mini (Legacy)",
            opts = { can_reason = true, has_vision = true, has_function_calling = true },
          },
        },
      },
      ["reasoning.effort"] = {
        order = 2,
        mapping = "parameters",
        type = "enum",
        optional = true,
        desc = "Reasoning effort level. Available options depend on the model.",
        enabled = function(self)
          local model = self.schema.model.default
          if type(model) == "function" then
            model = model(self)
          end
          local choices = self.schema.model.choices
          if type(choices) == "function" then
            choices = choices(self)
          end
          return choices and choices[model] and choices[model].opts and choices[model].opts.can_reason
        end,
        default = function(self)
          local model = self.schema.model.default
          if type(model) == "function" then
            model = model(self)
          end
          return get_default_effort(model)
        end,
        choices = function(self)
          local model = self.schema.model.default
          if type(model) == "function" then
            model = model(self)
          end
          return get_effort_choices(model)
        end,
      },
      ["reasoning.summary"] = {
        order = 3,
        mapping = "parameters",
        type = "enum",
        optional = true,
        desc = "Summary style for reasoning output.",
        enabled = function(self)
          local model = self.schema.model.default
          if type(model) == "function" then
            model = model(self)
          end
          local choices = self.schema.model.choices
          if type(choices) == "function" then
            choices = choices(self)
          end
          return choices and choices[model] and choices[model].opts and choices[model].opts.can_reason
        end,
        default = function(self)
          local effort = self.schema["reasoning.effort"].default
          if type(effort) == "function" then
            effort = effort(self)
          end
          return (effort == "high" or effort == "xhigh") and "detailed" or "auto"
        end,
        choices = { "auto", "concise", "detailed" },
      },
      verbosity = {
        order = 4,
        mapping = "parameters.text",
        type = "enum",
        optional = true,
        default = "medium",
        desc = "Controls output verbosity. Use 'high' for thorough explanations, 'low' for concise answers.",
        choices = { "low", "medium", "high" },
      },
    },

    -- Expose get_access_token for external use
    get_access_token = get_access_token,
  }
end

return M
