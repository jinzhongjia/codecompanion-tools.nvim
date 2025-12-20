-- Gemini (Code Assist) OAuth adapter for CodeCompanion
-- Provides OAuth 2.0 + PKCE authentication for Google Gemini API

local curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local oauth_utils = require("codecompanion-tools.adapters.oauth_utils")

local M = {}

-- Module-level token cache
local _access_token = nil
local _refresh_token = nil
local _token_expires = nil
local _project_id = nil
local _token_loaded = false

-- OAuth flow constant configuration
local OAUTH_CONFIG = {
  CLIENT_ID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com",
  CLIENT_SECRET = "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",
  REDIRECT_URI = "http://localhost:8085/oauth2callback",
  AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth",
  TOKEN_URL = "https://oauth2.googleapis.com/token",
  SCOPES = {
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
  },
  CALLBACK_PORT = 8085,
  ACCESS_TOKEN_EXPIRY_BUFFER_MS = 60 * 1000,
  TOKEN_FILE = "gemini_oauth.json",
}

-- Code Assist API configuration
local CODE_ASSIST_CONFIG = {
  ENDPOINT = "https://cloudcode-pa.googleapis.com",
  HEADERS = {
    ["User-Agent"] = "google-api-nodejs-client/9.15.1",
    ["X-Goog-Api-Client"] = "gl-node/22.17.0",
    ["Client-Metadata"] = "ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI",
  },
}

-- Success HTML for OAuth callback
local SUCCESS_HTML = [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Gemini OAuth - CodeCompanion</title>
    <style>
        :root { color-scheme: light dark; }
        body {
            margin: 0; min-height: 100vh;
            display: flex; align-items: center; justify-content: center;
            font-family: "Roboto", "Google Sans", arial, sans-serif;
            background: #f1f3f4; color: #202124;
        }
        main {
            width: min(448px, calc(100% - 3rem));
            background: #ffffff; border-radius: 28px;
            padding: 2.5rem 2.75rem;
            box-shadow: 0 1px 2px rgba(60,64,67,.3), 0 2px 6px rgba(60,64,67,.15);
        }
        h1 { margin: 0 0 0.75rem; font-size: 1.75rem; font-weight: 500; }
        p { margin: 0 0 1.75rem; font-size: 1.05rem; line-height: 1.6; color: #3c4043; }
        .action {
            display: inline-flex; padding: 0.65rem 1.85rem;
            border-radius: 999px; background: #1a73e8; color: #fff;
            font-weight: 500; text-decoration: none;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #131314; color: #e8eaed; }
            main { background: #202124; }
            p { color: #e8eaed; }
            .action { background: #8ab4f8; color: #202124; }
        }
    </style>
</head>
<body>
    <main>
        <h1>Authentication Successful!</h1>
        <p>Your Google account is now linked to CodeCompanion. You can close this window and return to Neovim.</p>
        <a class="action" href="javascript:window.close()">Close window</a>
    </main>
</body>
</html>]]

---Get OAuth token file path
---@return string|nil
local function get_token_file_path()
  return oauth_utils.get_token_file_path(OAUTH_CONFIG.TOKEN_FILE, "CODECOMPANION_GEMINI_TOKEN_PATH")
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
    _project_id = data.project_id
    return _refresh_token ~= nil
  end

  return false
end

---Save tokens to file
---@param access_token string
---@param refresh_token string
---@param expires number
---@param project_id string|nil
---@return boolean
local function save_tokens(access_token, refresh_token, expires, project_id)
  if not refresh_token or refresh_token == "" then
    log:error("Gemini OAuth: Cannot save without refresh token")
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
    project_id = project_id,
    created_at = os.time(),
    version = 1,
  }

  if oauth_utils.save_json_file(token_file, data) then
    _access_token = access_token
    _refresh_token = refresh_token
    _token_expires = expires
    _project_id = project_id
    _token_loaded = true
    log:info("Gemini OAuth: Tokens saved successfully")
    return true
  end

  log:error("Gemini OAuth: Failed to save tokens")
  return false
end

---Load managed project from Code Assist API
---@param access_token string
---@return string|nil
local function load_managed_project(access_token)
  log:debug("Gemini OAuth: Loading managed project")

  local request_body = {
    metadata = {
      ideType = "IDE_UNSPECIFIED",
      platform = "PLATFORM_UNSPECIFIED",
      pluginType = "GEMINI",
    },
  }

  local success, body_json = pcall(vim.json.encode, request_body)
  if not success then
    log:error("Gemini OAuth: Failed to encode request body")
    return nil
  end

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  local response = curl.post(CODE_ASSIST_CONFIG.ENDPOINT .. "/v1internal:loadCodeAssist", {
    headers = vim.tbl_extend("force", {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. access_token,
    }, CODE_ASSIST_CONFIG.HEADERS),
    body = body_json,
    insecure = http_opts.allow_insecure,
    proxy = http_opts.proxy,
    timeout = 30000,
    on_error = function(err)
      log:error("Gemini OAuth: Load managed project error: %s", vim.inspect(err))
    end,
  })

  if not response or response.status >= 400 then
    log:debug("Gemini OAuth: No existing managed project found, will try to onboard")
    return nil
  end

  local decode_success, data = pcall(vim.json.decode, response.body)
  if decode_success and data and data.cloudaicompanionProject then
    log:debug("Gemini OAuth: Found managed project: %s", data.cloudaicompanionProject)
    return data.cloudaicompanionProject
  end

  return nil
end

---Onboard user to get managed project
---@param access_token string
---@return string|nil
local function onboard_managed_project(access_token)
  log:debug("Gemini OAuth: Onboarding user to get managed project")

  local request_body = {
    tierId = "FREE",
    metadata = {
      ideType = "IDE_UNSPECIFIED",
      platform = "PLATFORM_UNSPECIFIED",
      pluginType = "GEMINI",
    },
  }

  local success, body_json = pcall(vim.json.encode, request_body)
  if not success then
    log:error("Gemini OAuth: Failed to encode onboard request body")
    return nil
  end

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  for attempt = 1, 10 do
    local response = curl.post(CODE_ASSIST_CONFIG.ENDPOINT .. "/v1internal:onboardUser", {
      headers = vim.tbl_extend("force", {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. access_token,
      }, CODE_ASSIST_CONFIG.HEADERS),
      body = body_json,
      insecure = http_opts.allow_insecure,
      proxy = http_opts.proxy,
      timeout = 30000,
      on_error = function(err)
        log:error("Gemini OAuth: Onboard error: %s", vim.inspect(err))
      end,
    })

    if response and response.status < 400 then
      local decode_success, data = pcall(vim.json.decode, response.body)
      if decode_success and data then
        local project_id = data.response
          and data.response.cloudaicompanionProject
          and data.response.cloudaicompanionProject.id
        if data.done and project_id then
          log:debug("Gemini OAuth: Onboarded with managed project: %s", project_id)
          return project_id
        end
      end
    end

    log:debug("Gemini OAuth: Onboard attempt %d failed, retrying...", attempt)
    vim.wait(5000)
  end

  log:error("Gemini OAuth: Failed to onboard after 10 attempts")
  return nil
end

---Ensure we have a valid project ID
---@param access_token string
---@return string|nil
local function ensure_project_id(access_token)
  local project_id = load_managed_project(access_token)
  if project_id then
    return project_id
  end

  return onboard_managed_project(access_token)
end

---Refresh access token using refresh token
---@return string|nil
local function refresh_access_token()
  if not _refresh_token or _refresh_token == "" then
    log:error("Gemini OAuth: No refresh token available")
    return nil
  end

  log:debug("Gemini OAuth: Refreshing access token")

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  local response = curl.post(OAUTH_CONFIG.TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = "grant_type=refresh_token"
      .. "&refresh_token="
      .. oauth_utils.url_encode(_refresh_token)
      .. "&client_id="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID)
      .. "&client_secret="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_SECRET),
    insecure = http_opts.allow_insecure,
    proxy = http_opts.proxy,
    timeout = 30000,
    on_error = function(err)
      log:error("Gemini OAuth: Token refresh error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Gemini OAuth: No response from token refresh request")
    return nil
  end

  if response.status >= 400 then
    log:error(
      "Gemini OAuth: Token refresh failed, status %d: %s",
      response.status,
      response.body or "no body"
    )
    local decode_ok, error_data = pcall(vim.json.decode, response.body)
    if decode_ok and error_data and error_data.error == "invalid_grant" then
      log:warn(
        "Gemini OAuth: Refresh token revoked. Please run :GeminiOAuthSetup to reauthenticate"
      )
      _access_token = nil
      _refresh_token = nil
      _token_expires = nil
      _project_id = nil
    end
    return nil
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data or not token_data.access_token then
    log:error("Gemini OAuth: Invalid token refresh response")
    return nil
  end

  local expires = os.time() * 1000 + (token_data.expires_in or 3600) * 1000
  local new_refresh = token_data.refresh_token or _refresh_token
  local project_id = _project_id or ensure_project_id(token_data.access_token)

  if save_tokens(token_data.access_token, new_refresh, expires, project_id) then
    log:debug("Gemini OAuth: Access token refreshed successfully")
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
    log:error("Gemini OAuth: Authorization code and verifier required")
    return false
  end

  log:debug("Gemini OAuth: Exchanging authorization code for tokens")

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  local response = curl.post(OAUTH_CONFIG.TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = "client_id="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID)
      .. "&client_secret="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_SECRET)
      .. "&code="
      .. oauth_utils.url_encode(code)
      .. "&grant_type=authorization_code"
      .. "&redirect_uri="
      .. oauth_utils.url_encode(OAUTH_CONFIG.REDIRECT_URI)
      .. "&code_verifier="
      .. oauth_utils.url_encode(verifier),
    insecure = http_opts.allow_insecure,
    proxy = http_opts.proxy,
    timeout = 30000,
    on_error = function(err)
      log:error("Gemini OAuth: Token exchange error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Gemini OAuth: No response from token exchange request")
    return false
  end

  if response.status >= 400 then
    log:error(
      "Gemini OAuth: Token exchange failed, status %d: %s",
      response.status,
      response.body or "no body"
    )
    return false
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data then
    log:error("Gemini OAuth: Invalid token exchange response")
    return false
  end

  if not token_data.access_token or not token_data.refresh_token then
    log:error("Gemini OAuth: Missing tokens in response")
    return false
  end

  local expires = os.time() * 1000 + (token_data.expires_in or 3600) * 1000

  log:debug("Gemini OAuth: Getting managed project ID")
  local project_id = ensure_project_id(token_data.access_token)
  if not project_id then
    log:error("Gemini OAuth: Failed to get managed project ID")
    return false
  end

  return save_tokens(token_data.access_token, token_data.refresh_token, expires, project_id)
end

---Encode state for OAuth (base64url)
---@param verifier string
---@return string
local function encode_state(verifier)
  local state_data = vim.json.encode({ verifier = verifier, projectId = "" })
  local base64 = vim.base64.encode(state_data)
  return base64:gsub("[+/=]", { ["+"] = "-", ["/"] = "_", ["="] = "" })
end

---Generate OAuth authorization URL
---@return { url: string, verifier: string, state: string }|nil
local function generate_auth_url()
  local pkce = oauth_utils.generate_pkce(64)
  if not pkce then
    return nil
  end

  local state = encode_state(pkce.verifier)

  local query_params = {
    "client_id=" .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID),
    "response_type=code",
    "redirect_uri=" .. oauth_utils.url_encode(OAUTH_CONFIG.REDIRECT_URI),
    "scope=" .. oauth_utils.url_encode(table.concat(OAUTH_CONFIG.SCOPES, " ")),
    "code_challenge=" .. oauth_utils.url_encode(pkce.challenge),
    "code_challenge_method=S256",
    "state=" .. oauth_utils.url_encode(state),
    "access_type=offline",
    "prompt=consent",
  }

  local auth_url = OAUTH_CONFIG.AUTH_URL .. "?" .. table.concat(query_params, "&")
  log:debug("Gemini OAuth: Authorization URL generated")

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

  if
    _access_token
    and not oauth_utils.is_token_expired(_token_expires, OAUTH_CONFIG.ACCESS_TOKEN_EXPIRY_BUFFER_MS)
  then
    return _access_token, _project_id
  end

  if _refresh_token then
    local new_token = refresh_access_token()
    if new_token then
      return new_token, _project_id
    end
  end

  log:error(
    "Gemini OAuth: Access token not available. Please run :GeminiOAuthSetup to authenticate"
  )
  return nil, nil
end

---Setup OAuth authentication (interactive)
---@return boolean
local function setup_oauth()
  local auth_data = generate_auth_url()
  if not auth_data then
    vim.notify(
      "Unable to generate Gemini OAuth authorization URL, please check logs.",
      vim.log.levels.ERROR
    )
    return false
  end

  vim.notify("Starting Gemini OAuth authentication...", vim.log.levels.INFO)

  oauth_utils.start_oauth_server(
    OAUTH_CONFIG.CALLBACK_PORT,
    "/oauth2callback",
    nil,
    SUCCESS_HTML,
    function(code, err, state)
      if err then
        vim.notify("Gemini OAuth failed: " .. err, vim.log.levels.ERROR)
        return
      end

      if not state or state ~= auth_data.state then
        vim.notify("Gemini OAuth failed: State mismatch (CSRF detected)", vim.log.levels.ERROR)
        return
      end

      if code then
        vim.notify("Authorization code received, exchanging for tokens...", vim.log.levels.INFO)
        if exchange_code_for_tokens(code, auth_data.verifier) then
          vim.notify("Gemini OAuth authentication successful!", vim.log.levels.INFO)
        else
          vim.notify("Gemini OAuth: Failed to exchange code for tokens", vim.log.levels.ERROR)
        end
      end
    end
  )

  local success = oauth_utils.open_url(auth_data.url)
  if not success then
    vim.notify(
      "Unable to automatically open browser. Please manually open this URL:\n" .. auth_data.url,
      vim.log.levels.WARN
    )
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
    vim.notify(
      "Gemini OAuth: Not authenticated. Run :CCTools adapter gemini auth",
      vim.log.levels.WARN
    )
    return
  end

  local status = "Gemini OAuth: Authenticated"
  if _project_id then
    status = status .. " (Project: " .. _project_id .. ")"
  end
  if
    _access_token
    and not oauth_utils.is_token_expired(_token_expires, OAUTH_CONFIG.ACCESS_TOKEN_EXPIRY_BUFFER_MS)
  then
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
      _project_id = nil
      _token_loaded = false
      vim.notify("Gemini OAuth: Tokens cleared.", vim.log.levels.INFO)
    else
      vim.notify("Gemini OAuth: Failed to clear token file.", vim.log.levels.ERROR)
    end
  else
    vim.notify("Gemini OAuth: No tokens to clear.", vim.log.levels.WARN)
  end
end

---Create the adapter
---@return table
function M.create_adapter()
  local adapter = {
    name = "gemini_oauth",
    formatted_name = "Gemini (OAuth)",
    roles = {
      llm = "model",
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
    url = CODE_ASSIST_CONFIG.ENDPOINT .. "/v1internal:streamGenerateContent?alt=sse",
    env = {
      api_key = function()
        local token, _ = get_access_token()
        return token
      end,
    },
    headers = {
      ["Authorization"] = "Bearer ${api_key}",
      ["Content-Type"] = "application/json",
      ["User-Agent"] = CODE_ASSIST_CONFIG.HEADERS["User-Agent"],
      ["X-Goog-Api-Client"] = CODE_ASSIST_CONFIG.HEADERS["X-Goog-Api-Client"],
      ["Client-Metadata"] = CODE_ASSIST_CONFIG.HEADERS["Client-Metadata"],
    },
    handlers = {
      setup = function(self)
        local access_token, project_id = get_access_token()
        if not access_token then
          vim.notify(
            "Gemini OAuth: Not authenticated. Run :GeminiOAuthSetup to authenticate.",
            vim.log.levels.ERROR
          )
          return false
        end
        if not project_id then
          vim.notify(
            "Gemini OAuth: No project ID. Run :GeminiOAuthSetup to reauthenticate.",
            vim.log.levels.ERROR
          )
          return false
        end

        self._project_id = project_id

        local model = self.schema.model.default
        local model_opts = self.schema.model.choices[model]
        if model_opts and model_opts.opts then
          self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
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

        if ok then
          local response = json.response or json
          if response and response.usageMetadata then
            return response.usageMetadata.totalTokenCount
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
        local contents = {}
        local system_instruction = nil
        local messages = payload.messages or {}

        for _, msg in ipairs(messages) do
          if msg.role == "system" then
            if not system_instruction then
              system_instruction = { parts = {} }
            end
            table.insert(system_instruction.parts, { text = msg.content })
          elseif msg.role == "user" or msg.role == "assistant" then
            local role = msg.role == "assistant" and "model" or "user"
            local parts = {}

            if msg._meta and msg._meta.tag == "image" and msg.context and msg.context.mimetype then
              table.insert(parts, {
                inlineData = {
                  mimeType = msg.context.mimetype,
                  data = msg.content,
                },
              })
            elseif type(msg.content) == "string" then
              table.insert(parts, { text = msg.content })
            elseif type(msg.content) == "table" then
              for _, part in ipairs(msg.content) do
                if part.type == "text" then
                  table.insert(parts, { text = part.text })
                elseif part.type == "image_url" then
                  local url = part.image_url and part.image_url.url
                  if url and string.match(url, "^data:") then
                    local mime, img_data = string.match(url, "^data:([^;]+);base64,(.+)$")
                    if mime and img_data then
                      table.insert(parts, {
                        inlineData = {
                          mimeType = mime,
                          data = img_data,
                        },
                      })
                    end
                  end
                end
              end
            end

            if #parts > 0 then
              table.insert(contents, { role = role, parts = parts })
            end
          end
        end

        local request = {
          contents = contents,
        }

        if system_instruction then
          request.systemInstruction = system_instruction
        end

        local model = self.schema.model.default
        local model_opts = self.schema.model.choices[model]
        if model_opts and model_opts.opts and model_opts.opts.can_reason then
          local thinking_config = { includeThoughts = true }
          if model_opts.opts.thinking_level then
            thinking_config.thinkingLevel = model_opts.opts.thinking_level
          elseif model_opts.opts.thinking_budget then
            thinking_config.thinkingBudget = model_opts.opts.thinking_budget
          else
            thinking_config.thinkingBudget = 8192
          end
          request.generationConfig = { thinkingConfig = thinking_config }
        end

        return {
          project = self._project_id or _project_id,
          model = model,
          request = request,
        }
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
          log:debug("Gemini OAuth: Failed to parse JSON: %s", json_str:sub(1, 200))
          return nil
        end

        local response = json.response or json

        if not response or not response.candidates or #response.candidates == 0 then
          return nil
        end

        local candidate = response.candidates[1]
        if not candidate or not candidate.content then
          return nil
        end

        local content = ""
        local thinking_content = ""
        local role = candidate.content.role == "model" and "assistant" or candidate.content.role

        if candidate.content.parts then
          for _, part in ipairs(candidate.content.parts) do
            if part.text then
              if part.thought then
                thinking_content = thinking_content .. part.text
              else
                content = content .. part.text
              end
            end
          end
        end

        if content == "" and thinking_content == "" then
          return nil
        end

        local output = {
          role = role,
          content = content ~= "" and content or nil,
        }

        if thinking_content ~= "" then
          output.reasoning = { content = thinking_content }
        end

        return {
          status = "success",
          output = output,
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
        default = "gemini-2.5-flash",
        choices = {
          ["gemini-3-pro-preview"] = {
            formatted_name = "Gemini 3 Pro (1M context)",
            opts = { can_reason = true, has_vision = true, thinking_level = "high", context_window = 1000000, max_output = 64000 },
          },
          ["gemini-3-flash-preview"] = {
            formatted_name = "Gemini 3 Flash (1M context)",
            opts = { can_reason = true, has_vision = true, thinking_level = "low", context_window = 1048576, max_output = 65536 },
          },
          ["gemini-2.5-pro"] = {
            formatted_name = "Gemini 2.5 Pro (1M context)",
            opts = { can_reason = true, has_vision = true, thinking_budget = 16384, context_window = 1048576, max_output = 65536 },
          },
          ["gemini-2.5-flash"] = {
            formatted_name = "Gemini 2.5 Flash (1M context)",
            opts = { can_reason = true, has_vision = true, thinking_budget = 8192, context_window = 1048576, max_output = 65536 },
          },
          ["gemini-2.5-flash-lite"] = {
            formatted_name = "Gemini 2.5 Flash Lite (1M context)",
            opts = { can_reason = true, has_vision = true, thinking_budget = 4096, context_window = 1048576, max_output = 65536 },
          },
          ["gemini-2.0-flash"] = {
            formatted_name = "Gemini 2.0 Flash (1M context)",
            opts = { has_vision = true, context_window = 1048576, max_output = 8192 },
          },
          ["gemini-2.0-flash-lite"] = {
            formatted_name = "Gemini 2.0 Flash Lite (1M context)",
            opts = { has_vision = true, context_window = 1048576, max_output = 8192 },
          },
          ["gemini-1.5-pro"] = {
            formatted_name = "Gemini 1.5 Pro (1M context)",
            opts = { has_vision = true, context_window = 1000000, max_output = 8192 },
          },
          ["gemini-1.5-flash"] = {
            formatted_name = "Gemini 1.5 Flash (1M context)",
            opts = { has_vision = true, context_window = 1000000, max_output = 8192 },
          },
        },
      },
      max_tokens = {
        order = 2,
        mapping = "parameters",
        type = "integer",
        optional = true,
        default = nil,
        desc = "The maximum number of tokens to include in a response candidate.",
        validate = function(n)
          return n > 0, "Must be greater than 0"
        end,
      },
      temperature = {
        order = 3,
        mapping = "parameters",
        type = "number",
        optional = true,
        default = nil,
        desc = "Controls the randomness of the output.",
        validate = function(n)
          return n >= 0 and n <= 2, "Must be between 0 and 2"
        end,
      },
    },
  }

  adapter.get_access_token = get_access_token

  return adapter
end

return M
