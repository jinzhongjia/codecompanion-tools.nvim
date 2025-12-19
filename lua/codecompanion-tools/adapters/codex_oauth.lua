-- Codex (ChatGPT) OAuth adapter for CodeCompanion
-- Provides OAuth 2.0 + PKCE authentication for OpenAI Codex API

local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local oauth_utils = require("codecompanion-tools.adapters.oauth_utils")

local M = {}

-- Module-level token cache
local _access_token = nil
local _refresh_token = nil
local _token_expires = nil
local _account_id = nil
local _token_loaded = false

-- OAuth flow constant configuration
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

-- Codex API configuration
local CODEX_CONFIG = {
  BASE_URL = "https://chatgpt.com/backend-api",
  ENDPOINT = "https://chatgpt.com/backend-api/codex/responses",
  HEADERS = {
    ["OpenAI-Beta"] = "responses=experimental",
    ["originator"] = "codex_cli_rs",
  },
  JWT_CLAIM_PATH = "https://api.openai.com/auth",
}

-- Success HTML for OAuth callback
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

  log:error("Codex OAuth: Access token not available. Please run :CodexOAuthSetup to authenticate")
  return nil, nil
end

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
      -- Verify state to prevent CSRF attacks
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

---Setup OAuth authentication (exported for unified command)
function M.setup_oauth()
  setup_oauth()
end

---Show OAuth status (exported for unified command)
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

---Clear OAuth tokens (exported for unified command)
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

---Update instructions from GitHub (exported for unified command)
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

  -- Get the instructions file path
  local info = debug.getinfo(1, "S")
  local current_file = info.source:sub(2)
  local dir = vim.fn.fnamemodify(current_file, ":h")
  local instructions_file = dir .. "/codex_instructions.lua"

  -- Generate the new file content
  local date = os.date("%Y-%m-%d")
  local new_content = string.format(
    [[-- Codex Instructions (fetched from https://github.com/openai/codex)
-- Last updated: %s
-- Run :CCTools adapter codex instructions to update from GitHub

local M = {}

M.INSTRUCTIONS = %s

M.SOURCE_URL = %q

return M
]],
    date,
    vim.inspect(response.body),
    codex_instructions.SOURCE_URL
  )

  -- Write the file
  local success, err = pcall(function()
    vim.fn.writefile(vim.split(new_content, "\n", { plain = true }), instructions_file)
  end)

  if success then
    package.loaded["codecompanion-tools.adapters.codex_instructions"] = nil
    vim.notify("Codex: Instructions updated successfully! Restart Neovim to apply.", vim.log.levels.INFO)
  else
    vim.notify("Codex: Failed to write instructions file: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end

---Create the adapter
---@return table
function M.create_adapter()
  local codex_instructions = require("codecompanion-tools.adapters.codex_instructions")

  local adapter = {
    name = "codex_oauth",
    formatted_name = "Codex (ChatGPT OAuth)",
    roles = {
      llm = "assistant",
      user = "user",
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
    headers = {
      ["Authorization"] = "Bearer ${api_key}",
      ["Content-Type"] = "application/json",
      ["Accept"] = "text/event-stream",
      ["OpenAI-Beta"] = CODEX_CONFIG.HEADERS["OpenAI-Beta"],
      ["originator"] = CODEX_CONFIG.HEADERS["originator"],
    },
    handlers = {
      setup = function(self)
        local access_token, account_id = get_access_token()
        if not access_token then
          vim.notify("Codex OAuth: Not authenticated. Run :CodexOAuthSetup to authenticate.", vim.log.levels.ERROR)
          return false
        end

        self._account_id = account_id

        if account_id then
          self.headers["chatgpt-account-id"] = account_id
        end

        return true
      end,

      tokens = function(self, data)
        if not data or data == "" then
          return nil
        end

        local data_str = type(data) == "table" and data.body or data
        if type(data_str) ~= "string" then
          return nil
        end

        local json_str = data_str:match("^data:%s*(.+)$") or data_str
        local ok, json = pcall(vim.json.decode, json_str, { luanil = { object = true } })

        if ok and json then
          if json.usage then
            return json.usage.total_tokens
          end
        end
        return nil
      end,

      form_parameters = function(self, params, messages)
        return {}
      end,

      form_messages = function(self, messages)
        return {}
      end,

      set_body = function(self, payload)
        local messages = payload.messages or {}

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

            if msg._meta and msg._meta.tag == "image" and msg.context and msg.context.mimetype then
              local next_msg = messages[i + 1]
              local combined_content = {
                { type = "input_image", image_url = string.format("data:%s;base64,%s", msg.context.mimetype, msg.content) },
              }
              if next_msg and next_msg.role == msg.role and type(next_msg.content) == "string" then
                table.insert(combined_content, { type = "input_text", text = next_msg.content })
                i = i + 1
              end
              table.insert(input, { role = msg.role, content = combined_content })
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

        local model = self.schema.model.default
        local model_opts = self.schema.model.choices[model]
        local opts = model_opts and model_opts.opts or {}

        local api_model = model
        if model:match("^gpt%-5%.2%-codex%-") then
          api_model = "gpt-5.2-codex"
        elseif model:match("^gpt%-5%.2%-") then
          api_model = "gpt-5.2"
        elseif model:match("^gpt%-5%.1%-codex%-max%-") then
          api_model = "gpt-5.1-codex-max"
        elseif model:match("^gpt%-5%.1%-codex%-mini%-") then
          api_model = "gpt-5.1-codex-mini"
        elseif model:match("^gpt%-5%.1%-codex%-") then
          api_model = "gpt-5.1-codex"
        elseif model:match("^gpt%-5%.1%-") then
          api_model = "gpt-5.1"
        end

        -- Add system instructions as developer message at the beginning of input
        -- (Codex API requires instructions field to contain only the original Codex system prompt)
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

        local body = {
          model = api_model,
          input = input,
          instructions = codex_instructions.INSTRUCTIONS,
          store = false,
          stream = true,
        }

        if opts.can_reason and opts.reasoning_effort then
          body.reasoning = {
            effort = opts.reasoning_effort,
            summary = opts.reasoning_summary or "auto",
          }
        end

        body.text = {
          verbosity = opts.text_verbosity or "medium",
        }

        body.include = { "reasoning.encrypted_content" }

        return body
      end,

      chat_output = function(self, data, tools)
        if not data or data == "" then
          return nil
        end

        local data_str = type(data) == "table" and data.body or data
        if type(data_str) ~= "string" then
          return nil
        end

        local json_str = data_str:match("^data:%s*(.+)$") or data_str
        if not json_str or json_str == "" or json_str == "[DONE]" then
          return nil
        end

        local ok, json = pcall(vim.json.decode, json_str, { luanil = { object = true } })
        if not ok then
          return nil
        end

        local content = ""
        local role = "assistant"

        if json.output and type(json.output) == "table" then
          for _, item in ipairs(json.output) do
            if item.type == "message" and item.content then
              for _, part in ipairs(item.content) do
                if part.type == "output_text" and part.text then
                  content = content .. part.text
                end
              end
            end
          end
        end

        if json.type == "response.output_text.delta" and json.delta then
          content = json.delta
        end

        if content == "" then
          return nil
        end

        return {
          status = "success",
          output = {
            role = role,
            content = content,
          },
        }
      end,

      inline_output = function(self, data, context)
        local result = self.handlers.chat_output(self, data, nil)
        if result and result.output and result.output.content then
          return {
            status = result.status,
            output = result.output.content,
          }
        end
        return nil
      end,

      on_exit = function(self, data)
        return nil
      end,
    },
    schema = {
      model = {
        order = 1,
        mapping = "parameters",
        type = "enum",
        desc = "The model that will complete your prompt.",
        default = "gpt-5.2-codex-medium",
        choices = {
          ["gpt-5.2-none"] = { formatted_name = "GPT-5.2 None", opts = { can_reason = true, has_vision = true, reasoning_effort = "none", reasoning_summary = "auto" } },
          ["gpt-5.2-low"] = { formatted_name = "GPT-5.2 Low", opts = { can_reason = true, has_vision = true, reasoning_effort = "low", reasoning_summary = "auto" } },
          ["gpt-5.2-medium"] = { formatted_name = "GPT-5.2 Medium", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "auto" } },
          ["gpt-5.2-high"] = { formatted_name = "GPT-5.2 High", opts = { can_reason = true, has_vision = true, reasoning_effort = "high", reasoning_summary = "detailed" } },
          ["gpt-5.2-xhigh"] = { formatted_name = "GPT-5.2 Extra High", opts = { can_reason = true, has_vision = true, reasoning_effort = "xhigh", reasoning_summary = "detailed" } },
          ["gpt-5.2-codex-low"] = { formatted_name = "GPT-5.2 Codex Low", opts = { can_reason = true, has_vision = true, reasoning_effort = "low", reasoning_summary = "detailed" } },
          ["gpt-5.2-codex-medium"] = { formatted_name = "GPT-5.2 Codex Medium", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "detailed" } },
          ["gpt-5.2-codex-high"] = { formatted_name = "GPT-5.2 Codex High", opts = { can_reason = true, has_vision = true, reasoning_effort = "high", reasoning_summary = "detailed" } },
          ["gpt-5.2-codex-xhigh"] = { formatted_name = "GPT-5.2 Codex Extra High", opts = { can_reason = true, has_vision = true, reasoning_effort = "xhigh", reasoning_summary = "detailed" } },
          ["gpt-5.1-codex-max-low"] = { formatted_name = "GPT-5.1 Codex Max Low", opts = { can_reason = true, has_vision = true, reasoning_effort = "low", reasoning_summary = "detailed" } },
          ["gpt-5.1-codex-max-medium"] = { formatted_name = "GPT-5.1 Codex Max Medium", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "detailed" } },
          ["gpt-5.1-codex-max-high"] = { formatted_name = "GPT-5.1 Codex Max High", opts = { can_reason = true, has_vision = true, reasoning_effort = "high", reasoning_summary = "detailed" } },
          ["gpt-5.1-codex-max-xhigh"] = { formatted_name = "GPT-5.1 Codex Max Extra High", opts = { can_reason = true, has_vision = true, reasoning_effort = "xhigh", reasoning_summary = "detailed" } },
          ["gpt-5.1-codex-low"] = { formatted_name = "GPT-5.1 Codex Low", opts = { can_reason = true, has_vision = true, reasoning_effort = "low", reasoning_summary = "auto" } },
          ["gpt-5.1-codex-medium"] = { formatted_name = "GPT-5.1 Codex Medium", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "auto" } },
          ["gpt-5.1-codex-high"] = { formatted_name = "GPT-5.1 Codex High", opts = { can_reason = true, has_vision = true, reasoning_effort = "high", reasoning_summary = "detailed" } },
          ["gpt-5.1-codex-mini-medium"] = { formatted_name = "GPT-5.1 Codex Mini Medium", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "auto" } },
          ["gpt-5.1-codex-mini-high"] = { formatted_name = "GPT-5.1 Codex Mini High", opts = { can_reason = true, has_vision = true, reasoning_effort = "high", reasoning_summary = "detailed" } },
          ["gpt-5.1-none"] = { formatted_name = "GPT-5.1 None", opts = { can_reason = true, has_vision = true, reasoning_effort = "none", reasoning_summary = "auto" } },
          ["gpt-5.1-low"] = { formatted_name = "GPT-5.1 Low", opts = { can_reason = true, has_vision = true, reasoning_effort = "low", reasoning_summary = "auto", text_verbosity = "low" } },
          ["gpt-5.1-medium"] = { formatted_name = "GPT-5.1 Medium", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "auto" } },
          ["gpt-5.1-high"] = { formatted_name = "GPT-5.1 High", opts = { can_reason = true, has_vision = true, reasoning_effort = "high", reasoning_summary = "detailed", text_verbosity = "high" } },
          ["codex-mini-latest"] = { formatted_name = "Codex Mini Latest", opts = { can_reason = true, has_vision = true, reasoning_effort = "medium", reasoning_summary = "auto" } },
        },
      },
    },
  }

  adapter.get_access_token = get_access_token

  return adapter
end

return M
