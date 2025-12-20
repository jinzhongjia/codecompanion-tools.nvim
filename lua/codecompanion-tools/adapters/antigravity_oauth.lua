-- Antigravity (Google Cloud Code Assist) OAuth adapter for CodeCompanion

local curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local oauth_utils = require("codecompanion-tools.adapters.oauth_utils")

local M = {}

local OAUTH_CONFIG = {
  CLIENT_ID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com",
  CLIENT_SECRET = "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",
  REDIRECT_URI = "http://localhost:51121/oauth-callback",
  AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth",
  TOKEN_URL = "https://oauth2.googleapis.com/token",
  SCOPES = {
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/cclog",
    "https://www.googleapis.com/auth/experimentsandconfigs",
  },
  CALLBACK_PORT = 51121,
  ACCESS_TOKEN_EXPIRY_BUFFER_MS = 60 * 1000,
  ACCOUNTS_FILE = "antigravity_accounts.json",
}

-- Antigravity API configuration with fallback endpoints
local ANTIGRAVITY_CONFIG = {
  ENDPOINTS = {
    "https://daily-cloudcode-pa.sandbox.googleapis.com",
    "https://autopush-cloudcode-pa.sandbox.googleapis.com",
    "https://cloudcode-pa.googleapis.com",
  },
  LOAD_ENDPOINTS = {
    "https://cloudcode-pa.googleapis.com",
    "https://daily-cloudcode-pa.sandbox.googleapis.com",
    "https://autopush-cloudcode-pa.sandbox.googleapis.com",
  },
  DEFAULT_PROJECT_ID = "rising-fact-p41fc",
  HEADERS = {
    ["User-Agent"] = "antigravity/1.11.5 windows/amd64",
    ["X-Goog-Api-Client"] = "google-cloud-sdk vscode_cloudshelleditor/0.1",
    ["Client-Metadata"] = '{"ideType":"IDE_UNSPECIFIED","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}',
  },
}

-- Success HTML for OAuth callback
local SUCCESS_HTML = [[<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Antigravity OAuth - CodeCompanion</title>
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

local _accounts = {}
local _cursor = 0
local _loaded = false

local function now_ms()
  return os.time() * 1000
end

local function get_accounts_file_path()
  return oauth_utils.get_token_file_path(OAUTH_CONFIG.ACCOUNTS_FILE)
end

local function load_accounts()
  if _loaded then
    return #_accounts > 0
  end
  _loaded = true

  local file_path = get_accounts_file_path()
  if not file_path then
    return false
  end

  local data = oauth_utils.load_json_file(file_path)
  if data and data.version == 1 and data.accounts then
    _accounts = {}
    for i, acc in ipairs(data.accounts) do
      if acc.refresh_token and acc.refresh_token ~= "" then
        table.insert(_accounts, {
          index = i,
          email = acc.email,
          refresh_token = acc.refresh_token,
          project_id = acc.project_id,
          access_token = nil,
          expires = nil,
          added_at = acc.added_at or now_ms(),
          last_used = acc.last_used or 0,
          is_rate_limited = acc.is_rate_limited or false,
          rate_limit_reset = acc.rate_limit_reset or 0,
        })
      end
    end
    _cursor = (data.active_index or 0) % math.max(1, #_accounts)
    return #_accounts > 0
  end

  return false
end

local function save_accounts()
  local file_path = get_accounts_file_path()
  if not file_path then
    return false
  end

  local data = {
    version = 1,
    accounts = {},
    active_index = _cursor,
  }

  for _, acc in ipairs(_accounts) do
    table.insert(data.accounts, {
      email = acc.email,
      refresh_token = acc.refresh_token,
      project_id = acc.project_id,
      added_at = acc.added_at,
      last_used = acc.last_used,
      is_rate_limited = acc.is_rate_limited,
      rate_limit_reset = acc.rate_limit_reset,
    })
  end

  return oauth_utils.save_json_file(file_path, data)
end

local function pick_next_account()
  local total = #_accounts
  if total == 0 then
    return nil
  end

  local now = now_ms()

  for _, acc in ipairs(_accounts) do
    if acc.is_rate_limited and acc.rate_limit_reset > 0 and now > acc.rate_limit_reset then
      acc.is_rate_limited = false
      acc.rate_limit_reset = 0
    end
  end

  for i = 0, total - 1 do
    local idx = ((_cursor + i) % total) + 1
    local acc = _accounts[idx]
    if acc and not acc.is_rate_limited then
      _cursor = idx % total
      acc.last_used = now
      return acc
    end
  end

  return nil
end

local function mark_rate_limited(account, retry_after_ms)
  account.is_rate_limited = true
  account.rate_limit_reset = now_ms() + (retry_after_ms or 60000)
  save_accounts()
end

local function add_account_data(refresh_token, project_id, email)
  for _, acc in ipairs(_accounts) do
    if acc.refresh_token == refresh_token then
      acc.project_id = project_id
      acc.email = email
      save_accounts()
      return acc
    end
  end

  local acc = {
    index = #_accounts + 1,
    email = email,
    refresh_token = refresh_token,
    project_id = project_id,
    access_token = nil,
    expires = nil,
    added_at = now_ms(),
    last_used = 0,
    is_rate_limited = false,
    rate_limit_reset = 0,
  }
  table.insert(_accounts, acc)
  save_accounts()
  return acc
end

local function remove_account_by_index(idx)
  if idx < 1 or idx > #_accounts then
    return false
  end

  table.remove(_accounts, idx)
  for i, acc in ipairs(_accounts) do
    acc.index = i
  end

  if #_accounts == 0 then
    _cursor = 0
  else
    if _cursor >= idx then
      _cursor = _cursor - 1
    end
    _cursor = _cursor % #_accounts
  end

  save_accounts()
  return true
end

---Load managed project from Antigravity API (tries multiple endpoints)
---@param access_token string
---@return string|nil
local function load_managed_project(access_token)
  log:debug("Antigravity OAuth: Loading managed project")

  local request_body = {
    metadata = {
      ideType = "IDE_UNSPECIFIED",
      platform = "PLATFORM_UNSPECIFIED",
      pluginType = "GEMINI",
    },
  }

  local success, body_json = pcall(vim.json.encode, request_body)
  if not success then
    log:error("Antigravity OAuth: Failed to encode request body")
    return nil
  end

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  for _, endpoint in ipairs(ANTIGRAVITY_CONFIG.LOAD_ENDPOINTS) do
    local response = curl.post(endpoint .. "/v1internal:loadCodeAssist", {
      headers = vim.tbl_extend("force", {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. access_token,
      }, ANTIGRAVITY_CONFIG.HEADERS),
      body = body_json,
      insecure = http_opts.allow_insecure,
      proxy = http_opts.proxy,
      timeout = 30000,
      on_error = function(err)
        log:debug(
          "Antigravity OAuth: Load managed project error at %s: %s",
          endpoint,
          vim.inspect(err)
        )
      end,
    })

    if response and response.status < 400 then
      local decode_success, data = pcall(vim.json.decode, response.body)
      if decode_success and data then
        local project_id = data.cloudaicompanionProject
        if type(project_id) == "table" and project_id.id then
          project_id = project_id.id
        end
        if project_id and project_id ~= "" then
          log:debug("Antigravity OAuth: Found managed project: %s (from %s)", project_id, endpoint)
          return project_id
        end
      end
    end
    log:debug("Antigravity OAuth: No project found at %s, trying next endpoint", endpoint)
  end

  log:debug("Antigravity OAuth: No existing managed project found, will use default")
  return nil
end

---Onboard user to get managed project
---@param access_token string
---@return string|nil
local function onboard_managed_project(access_token)
  log:debug("Antigravity OAuth: Attempting to onboard user")

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
    log:error("Antigravity OAuth: Failed to encode onboard request body")
    return nil
  end

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  local endpoint = ANTIGRAVITY_CONFIG.LOAD_ENDPOINTS[1]
  local response = curl.post(endpoint .. "/v1internal:onboardUser", {
    headers = vim.tbl_extend("force", {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. access_token,
    }, ANTIGRAVITY_CONFIG.HEADERS),
    body = body_json,
    insecure = http_opts.allow_insecure,
    proxy = http_opts.proxy,
    timeout = 30000,
    on_error = function(err)
      log:debug("Antigravity OAuth: Onboard error: %s", vim.inspect(err))
    end,
  })

  if response and response.status < 400 then
    local decode_success, data = pcall(vim.json.decode, response.body)
    if decode_success and data then
      local project_id = data.response
        and data.response.cloudaicompanionProject
        and data.response.cloudaicompanionProject.id
      if data.done and project_id then
        log:debug("Antigravity OAuth: Onboarded with managed project: %s", project_id)
        return project_id
      end
    end
  end

  log:debug("Antigravity OAuth: Onboard not available, will use default project")
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

  project_id = onboard_managed_project(access_token)
  if project_id then
    return project_id
  end

  log:debug(
    "Antigravity OAuth: Using default project ID: %s",
    ANTIGRAVITY_CONFIG.DEFAULT_PROJECT_ID
  )
  return ANTIGRAVITY_CONFIG.DEFAULT_PROJECT_ID
end

local function refresh_account_token(account)
  if not account or not account.refresh_token then
    return nil
  end

  log:debug("Antigravity OAuth: Refreshing token for account #%d", account.index)

  local http_opts = config.adapters and config.adapters.http and config.adapters.http.opts or {}

  local response = curl.post(OAUTH_CONFIG.TOKEN_URL, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = "grant_type=refresh_token"
      .. "&refresh_token="
      .. oauth_utils.url_encode(account.refresh_token)
      .. "&client_id="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_ID)
      .. "&client_secret="
      .. oauth_utils.url_encode(OAUTH_CONFIG.CLIENT_SECRET),
    insecure = http_opts.allow_insecure,
    proxy = http_opts.proxy,
    timeout = 30000,
    on_error = function(err)
      log:error("Antigravity OAuth: Token refresh error: %s", vim.inspect(err))
    end,
  })

  if not response then
    return nil
  end

  if response.status >= 400 then
    log:error("Antigravity OAuth: Token refresh failed for account #%d, status %d", account.index, response.status)
    local decode_ok, error_data = pcall(vim.json.decode, response.body)
    if decode_ok and error_data and error_data.error == "invalid_grant" then
      log:warn("Antigravity OAuth: Account #%d refresh token revoked", account.index)
    end
    return nil
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data or not token_data.access_token then
    return nil
  end

  local expires = os.time() * 1000 + (token_data.expires_in or 3600) * 1000
  account.access_token = token_data.access_token
  account.expires = expires

  if token_data.refresh_token then
    account.refresh_token = token_data.refresh_token
  end

  if not account.project_id then
    account.project_id = ensure_project_id(token_data.access_token)
  end

  save_accounts()
  log:debug("Antigravity OAuth: Token refreshed for account #%d", account.index)
  return token_data.access_token
end

---Exchange authorization code for tokens
---@param code string
---@param verifier string
---@return boolean
local function exchange_code_for_tokens(code, verifier)
  if not code or code == "" or not verifier or verifier == "" then
    log:error("Antigravity OAuth: Authorization code and verifier required")
    return false
  end

  log:debug("Antigravity OAuth: Exchanging authorization code for tokens")

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
      log:error("Antigravity OAuth: Token exchange error: %s", vim.inspect(err))
    end,
  })

  if not response then
    log:error("Antigravity OAuth: No response from token exchange request")
    return false
  end

  if response.status >= 400 then
    log:error(
      "Antigravity OAuth: Token exchange failed, status %d: %s",
      response.status,
      response.body or "no body"
    )
    return false
  end

  local decode_success, token_data = pcall(vim.json.decode, response.body)
  if not decode_success or not token_data then
    log:error("Antigravity OAuth: Invalid token exchange response")
    return false
  end

  if not token_data.access_token or not token_data.refresh_token then
    log:error("Antigravity OAuth: Missing tokens in response")
    return false
  end

  local expires = os.time() * 1000 + (token_data.expires_in or 3600) * 1000

  log:debug("Antigravity OAuth: Getting managed project ID")
  local project_id = ensure_project_id(token_data.access_token)

  local account = add_account_data(token_data.refresh_token, project_id, nil)
  account.access_token = token_data.access_token
  account.expires = expires
  save_accounts()

  log:info("Antigravity OAuth: Account added successfully (total: %d)", #_accounts)
  return true
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
---@return { url: string, verifier: string }|nil
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
  log:debug("Antigravity OAuth: Authorization URL generated")

  return {
    url = auth_url,
    verifier = pkce.verifier,
  }
end

local function get_access_token()
  if not _loaded then
    load_accounts()
  end

  local account = pick_next_account()
  if not account then
    log:error("Antigravity OAuth: No accounts available. Run :CCTools adapter antigravity auth")
    return nil, nil
  end

  if account.access_token and not oauth_utils.is_token_expired(account.expires, OAUTH_CONFIG.ACCESS_TOKEN_EXPIRY_BUFFER_MS) then
    return account.access_token, account.project_id
  end

  local new_token = refresh_account_token(account)
  if new_token then
    return new_token, account.project_id
  end

  mark_rate_limited(account, 60000)
  log:warn("Antigravity OAuth: Account #%d token refresh failed, trying next", account.index)

  local next_account = pick_next_account()
  if next_account and next_account ~= account then
    local token = refresh_account_token(next_account)
    if token then
      return token, next_account.project_id
    end
  end

  log:error("Antigravity OAuth: All accounts exhausted")
  return nil, nil
end

---Setup OAuth authentication (interactive)
---@return boolean
local function setup_oauth()
  local auth_data = generate_auth_url()
  if not auth_data then
    vim.notify(
      "Unable to generate Antigravity OAuth authorization URL, please check logs.",
      vim.log.levels.ERROR
    )
    return false
  end

  vim.notify("Starting Antigravity OAuth authentication...", vim.log.levels.INFO)

  oauth_utils.start_oauth_server(
    OAUTH_CONFIG.CALLBACK_PORT,
    "/oauth-callback",
    nil,
    SUCCESS_HTML,
    function(code, err)
      if err then
        vim.notify("Antigravity OAuth failed: " .. err, vim.log.levels.ERROR)
        return
      end

      if code then
        vim.notify("Authorization code received, exchanging for tokens...", vim.log.levels.INFO)
        if exchange_code_for_tokens(code, auth_data.verifier) then
          vim.notify("Antigravity OAuth authentication successful!", vim.log.levels.INFO)
        else
          vim.notify("Antigravity OAuth: Failed to exchange code for tokens", vim.log.levels.ERROR)
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

---Generate a unique request ID
local function generate_request_id()
  local chars = "0123456789abcdef"
  local parts = {}
  local lengths = { 8, 4, 4, 4, 12 }
  for _, len in ipairs(lengths) do
    local part = {}
    for _ = 1, len do
      local idx = math.random(1, #chars)
      table.insert(part, chars:sub(idx, idx))
    end
    table.insert(parts, table.concat(part))
  end
  return "agent-" .. table.concat(parts, "-")
end

local function generate_session_id()
  local parts = {}
  for _ = 1, 19 do
    table.insert(parts, tostring(math.random(0, 9)))
  end
  return "-" .. table.concat(parts)
end

function M.setup_oauth()
  setup_oauth()
end

function M.add_account()
  setup_oauth()
end

function M.show_status()
  load_accounts()
  if #_accounts == 0 then
    vim.notify("Antigravity OAuth: No accounts. Run :CCTools adapter antigravity auth", vim.log.levels.WARN)
    return
  end

  local lines = { string.format("Antigravity OAuth: %d account(s)", #_accounts) }
  for i, acc in ipairs(_accounts) do
    local status = acc.is_rate_limited and "rate-limited" or "active"
    local token_status = ""
    if acc.access_token and not oauth_utils.is_token_expired(acc.expires, OAUTH_CONFIG.ACCESS_TOKEN_EXPIRY_BUFFER_MS) then
      token_status = " [valid]"
    end
    local email = acc.email or "unknown"
    table.insert(lines, string.format("  #%d: %s (%s)%s", i, email, status, token_status))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.list_accounts()
  M.show_status()
end

function M.remove_account(index)
  load_accounts()
  if type(index) == "string" then
    index = tonumber(index)
  end

  if not index then
    vim.ui.input({ prompt = "Enter account number to remove: " }, function(input)
      if input then
        M.remove_account(tonumber(input))
      end
    end)
    return
  end

  if index < 1 or index > #_accounts then
    vim.notify(string.format("Antigravity OAuth: Invalid account number %d (have %d accounts)", index, #_accounts), vim.log.levels.ERROR)
    return
  end

  local acc = _accounts[index]
  local email = acc.email or "unknown"

  if remove_account_by_index(index) then
    vim.notify(string.format("Antigravity OAuth: Removed account #%d (%s). %d remaining.", index, email, #_accounts), vim.log.levels.INFO)
  else
    vim.notify("Antigravity OAuth: Failed to remove account", vim.log.levels.ERROR)
  end
end

function M.clear_tokens()
  local file_path = get_accounts_file_path()
  if file_path and vim.fn.filereadable(file_path) == 1 then
    local success = pcall(vim.fn.delete, file_path)
    if success then
      _accounts = {}
      _cursor = 0
      _loaded = false
      vim.notify("Antigravity OAuth: All accounts cleared.", vim.log.levels.INFO)
    else
      vim.notify("Antigravity OAuth: Failed to clear accounts file.", vim.log.levels.ERROR)
    end
  else
    vim.notify("Antigravity OAuth: No accounts to clear.", vim.log.levels.WARN)
  end
end

---Create the adapter
---@return table
function M.create_adapter()
  local adapter = {
    name = "antigravity_oauth",
    formatted_name = "Antigravity (OAuth)",
    roles = {
      llm = "model",
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
    url = ANTIGRAVITY_CONFIG.ENDPOINTS[1] .. "/v1internal:streamGenerateContent?alt=sse",
    env = {
      api_key = function()
        local token, _ = get_access_token()
        return token
      end,
    },
    headers = {
      ["Authorization"] = "Bearer ${api_key}",
      ["Content-Type"] = "application/json",
      ["User-Agent"] = ANTIGRAVITY_CONFIG.HEADERS["User-Agent"],
      ["X-Goog-Api-Client"] = ANTIGRAVITY_CONFIG.HEADERS["X-Goog-Api-Client"],
      ["Client-Metadata"] = ANTIGRAVITY_CONFIG.HEADERS["Client-Metadata"],
    },
    handlers = {
      setup = function(self)
        local access_token, project_id = get_access_token()
        if not access_token then
          vim.notify(
            "Antigravity OAuth: Not authenticated. Run :CCTools adapter antigravity auth",
            vim.log.levels.ERROR
          )
          return false
        end
        if not project_id then
          vim.notify(
            "Antigravity OAuth: No project ID. Run :CCTools adapter antigravity auth",
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

      form_tools = function(self, tools)
        return nil
      end,

      set_body = function(self, payload)
        local contents = {}
        local system_instruction = nil
        local messages = payload.messages or {}

        local function add_content(role, parts)
          if #parts == 0 then
            return
          end
          local last = contents[#contents]
          if last and last.role == role then
            for _, p in ipairs(parts) do
              table.insert(last.parts, p)
            end
          else
            table.insert(contents, { role = role, parts = parts })
          end
        end

        for _, msg in ipairs(messages) do
          if msg.role == "system" then
            if not system_instruction then
              system_instruction = { parts = {} }
            end
            table.insert(system_instruction.parts, { text = msg.content })
          elseif msg.role == "tool" then
            local parts = {}
            if msg.content and type(msg.content) == "table" then
              for _, part in ipairs(msg.content) do
                if part.functionResponse then
                  table.insert(parts, part)
                end
              end
            end
            add_content("user", parts)
          elseif msg.role == "user" or msg.role == "assistant" then
            local role = msg.role == "assistant" and "model" or "user"
            local parts = {}

            if msg.tools and msg.tools.calls then
              for _, tool_call in ipairs(msg.tools.calls) do
                local args = {}
                if tool_call["function"] and tool_call["function"].arguments then
                  local decode_ok, decoded = pcall(vim.json.decode, tool_call["function"].arguments)
                  if decode_ok then
                    args = decoded
                  end
                end
                local fc = {
                  name = tool_call["function"].name,
                  args = args,
                }
                if tool_call.thoughtSignature then
                  fc.thoughtSignature = tool_call.thoughtSignature
                end
                table.insert(parts, { functionCall = fc })
              end
            end

            if msg._meta and msg._meta.tag == "image" and msg.context and msg.context.mimetype then
              table.insert(parts, {
                inlineData = {
                  mimeType = msg.context.mimetype,
                  data = msg.content,
                },
              })
            elseif type(msg.content) == "string" and msg.content ~= "" then
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

            add_content(role, parts)
          end
        end

        local request = {
          contents = contents,
        }

        if system_instruction then
          request.systemInstruction = system_instruction
        end

        if self.opts.tools and payload.tools and vim.tbl_count(payload.tools) > 0 then
          local declarations = {}
          for _, tool in pairs(payload.tools) do
            for _, schema in pairs(tool) do
              if schema.type == "function" and schema["function"] then
                local params = schema["function"].parameters
                if params then
                  params = vim.deepcopy(params)
                  if params.properties then
                    for prop_name, prop in pairs(params.properties) do
                      if prop.enum and #prop.enum > 0 then
                        local string_enum = {}
                        for _, v in ipairs(prop.enum) do
                          table.insert(string_enum, tostring(v))
                        end
                        params.properties[prop_name].enum = string_enum
                        if prop.type == "integer" or prop.type == "number" then
                          params.properties[prop_name].type = "string"
                        end
                      end
                    end
                  end
                end
                table.insert(declarations, {
                  name = schema["function"].name,
                  description = schema["function"].description,
                  parameters = params,
                })
              end
            end
          end
          if #declarations > 0 then
            request.tools = { { functionDeclarations = declarations } }
          end
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

        request.sessionId = generate_session_id()

        return {
          project = self._project_id,
          model = model,
          request = request,
          userAgent = "antigravity",
          requestId = generate_request_id(),
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
          log:debug("Antigravity OAuth: Failed to parse JSON: %s", json_str:sub(1, 200))
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
        local thinking = ""
        local role = candidate.content.role == "model" and "assistant" or candidate.content.role

        if candidate.content.parts then
          for i, part in ipairs(candidate.content.parts) do
            if part.functionCall and tools then
              local args = part.functionCall.args or {}
              local args_json = ""
              local encode_ok, encoded = pcall(vim.json.encode, args)
              if encode_ok then
                args_json = encoded
              end

              local found = false
              for _, existing_tool in ipairs(tools) do
                if existing_tool._index == i then
                  if args_json ~= "" then
                    existing_tool["function"]["arguments"] = (existing_tool["function"]["arguments"] or "") .. args_json
                  end
                  if part.thoughtSignature then
                    existing_tool.thoughtSignature = part.thoughtSignature
                  end
                  found = true
                  break
                end
              end

              if not found then
                local call_id = string.format("call_%s_%d", generate_request_id():sub(7), i)
                local tool_data = {
                  _index = i,
                  id = call_id,
                  type = "function",
                  ["function"] = {
                    name = part.functionCall.name,
                    arguments = args_json,
                  },
                }
                if part.thoughtSignature then
                  tool_data.thoughtSignature = part.thoughtSignature
                end
                table.insert(tools, tool_data)
              end
            elseif part.text then
              if part.thought then
                thinking = thinking .. part.text
              else
                content = content .. part.text
              end
            end
          end
        end

        if content == "" and thinking == "" and not role and (not tools or #tools == 0) then
          return nil
        end

        local output = {
          role = role,
          content = content,
        }

        local extra = nil
        if thinking ~= "" then
          extra = { thinking_content = thinking }
        end

        return {
          status = "success",
          output = output,
          extra = extra,
        }
      end,

      parse_message_meta = function(self, data)
        local extra = data.extra
        if extra and extra.thinking_content then
          data.output.reasoning = { content = extra.thinking_content }
          if data.output.content == "" then
            data.output.content = nil
          end
        end
        return data
      end,

      tools = {
        format_tool_calls = function(self, tool_calls)
          return tool_calls
        end,

        output_response = function(self, tool_call, output)
          return {
            role = "tool",
            content = {
              {
                functionResponse = {
                  name = tool_call["function"]["name"],
                  response = { result = output },
                },
              },
            },
          }
        end,
      },

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
          ["gemini-3-pro-high"] = {
            formatted_name = "Gemini 3 Pro High",
            opts = { can_reason = true, has_vision = true, thinking_level = "high", context = 1048576, output = 65535 },
          },
          ["gemini-3-pro-low"] = {
            formatted_name = "Gemini 3 Pro Low",
            opts = { can_reason = true, has_vision = true, thinking_level = "low", context = 1048576, output = 65535 },
          },
          ["gemini-3-flash"] = {
            formatted_name = "Gemini 3 Flash",
            opts = { can_reason = true, has_vision = true, thinking_level = "low", context = 1048576, output = 65536 },
          },
          ["gemini-2.5-pro"] = {
            formatted_name = "Gemini 2.5 Pro",
            opts = { can_reason = true, has_vision = true, thinking_budget = 16384 },
          },
          ["gemini-2.5-flash"] = {
            formatted_name = "Gemini 2.5 Flash",
            opts = { can_reason = true, has_vision = true, thinking_budget = 8192 },
          },
          ["gemini-2.0-flash"] = {
            formatted_name = "Gemini 2.0 Flash",
            opts = { has_vision = true },
          },
          ["gemini-2.0-flash-lite"] = {
            formatted_name = "Gemini 2.0 Flash Lite",
            opts = { has_vision = true },
          },
          ["gemini-1.5-pro"] = { formatted_name = "Gemini 1.5 Pro", opts = { has_vision = true } },
          ["gemini-1.5-flash"] = {
            formatted_name = "Gemini 1.5 Flash",
            opts = { has_vision = true },
          },
          ["claude-sonnet-4-5"] = {
            formatted_name = "Claude Sonnet 4.5",
            opts = { has_vision = true, context = 200000, output = 64000 },
          },
          ["claude-sonnet-4-5-thinking"] = {
            formatted_name = "Claude Sonnet 4.5 Thinking",
            opts = { can_reason = true, has_vision = true, thinking_budget = 10000, context = 200000, output = 64000 },
          },
          ["claude-opus-4-5-thinking"] = {
            formatted_name = "Claude Opus 4.5 Thinking",
            opts = { can_reason = true, has_vision = true, thinking_budget = 10000, context = 200000, output = 64000 },
          },
          ["gpt-oss-120b-medium"] = {
            formatted_name = "GPT-OSS 120B Medium",
            opts = { has_vision = false, context = 131072, output = 32768 },
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
