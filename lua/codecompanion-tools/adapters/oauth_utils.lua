-- OAuth utility functions shared across adapters
-- Provides common functionality for OAuth 2.0 + PKCE authentication

local M = {}

local uv = vim.uv or vim.loop
local Job = require("plenary.job")

---Trim whitespace from string
---@param str string|nil
---@return string
function M.trim(str)
  if type(str) ~= "string" then
    return ""
  end
  if vim.trim then
    return vim.trim(str)
  end
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

---URL encode a string
---@param str string
---@return string
function M.url_encode(str)
  if str then
    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
  end
  return str
end

---URL decode a string
---@param str string
---@return string
function M.url_decode(str)
  if not str then
    return ""
  end
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return str
end

---Parse query string from URL
---@param query string
---@return table
function M.parse_query_string(query)
  local params = {}
  if not query then
    return params
  end
  for pair in string.gmatch(query, "[^&]+") do
    local key, value = string.match(pair, "([^=]+)=?(.*)")
    if key then
      params[M.url_decode(key)] = M.url_decode(value or "")
    end
  end
  return params
end

---Read random bytes from /dev/urandom (Unix only)
---@param length number
---@return string|nil
local function read_random_from_file(length)
  if not uv then
    return nil
  end
  if vim.fn.has("win32") == 1 then
    return nil
  end
  local fd = uv.fs_open("/dev/urandom", "r", 438)
  if not fd then
    return nil
  end
  local data = uv.fs_read(fd, length, 0)
  uv.fs_close(fd)
  return data
end

---Read random bytes using PowerShell (Windows only)
---@param length number
---@return string|nil
local function read_random_from_windows(length)
  if vim.fn.has("win32") == 0 then
    return nil
  end

  local ps_exe = nil
  if vim.fn.executable("pwsh") == 1 then
    ps_exe = "pwsh"
  elseif vim.fn.executable("powershell") == 1 then
    ps_exe = "powershell"
  end
  if not ps_exe then
    return nil
  end

  local script = string.format(
    "$bytes = New-Object byte[] %d; "
      .. "[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes); "
      .. "[System.Convert]::ToBase64String($bytes)",
    length
  )
  local result = vim.fn.system({ ps_exe, "-NoProfile", "-Command", script })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local ok, decoded = pcall(vim.base64.decode, M.trim(result))
  if ok and decoded and #decoded >= length then
    return decoded:sub(1, length)
  end
  return nil
end

---Read random bytes using OpenSSL
---@param length number
---@return string|nil
local function read_random_from_openssl(length)
  if vim.fn.executable("openssl") == 0 then
    return nil
  end
  local result = vim.fn.system({ "openssl", "rand", "-base64", tostring(length) })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local ok, decoded = pcall(vim.base64.decode, M.trim(result))
  if ok and decoded and #decoded >= length then
    return decoded:sub(1, length)
  end
  return nil
end

---Generate secure random bytes (cross-platform)
---@param length number
---@return string|nil
function M.secure_random_bytes(length)
  local readers
  if vim.fn.has("win32") == 1 then
    readers = {
      function()
        return read_random_from_windows(length)
      end,
      function()
        return read_random_from_openssl(length)
      end,
    }
  else
    readers = {
      function()
        return read_random_from_file(length)
      end,
      function()
        return read_random_from_openssl(length)
      end,
    }
  end

  for _, reader in ipairs(readers) do
    local ok, bytes = pcall(reader)
    if ok and bytes and #bytes >= length then
      return bytes:sub(1, length)
    end
  end

  return nil
end

---Convert hex string to binary
---@param hex string
---@return string|nil
function M.hex_to_binary(hex)
  if not hex or hex == "" then
    return nil
  end
  local ok, binary = pcall(function()
    return hex:gsub("..", function(cc)
      local byte = tonumber(cc, 16)
      return byte and string.char(byte) or ""
    end)
  end)
  if ok and binary and binary ~= "" then
    return binary
  end
  return nil
end

---SHA256 hash using OpenSSL (returns binary)
---@param input string
---@return string|nil
function M.sha256_binary_openssl(input)
  if vim.fn.executable("openssl") == 0 then
    return nil
  end

  local job = Job:new({
    command = "openssl",
    args = { "dgst", "-sha256", "-binary" },
    writer = input,
    enable_recording = true,
    env = vim.fn.has("win32") == 1 and {
      PATH = vim.env.PATH,
      SYSTEMROOT = vim.env.SYSTEMROOT,
    } or nil,
  })

  local success = pcall(function()
    job:sync(3000)
  end)

  if not success or job.code ~= 0 then
    return nil
  end

  local result = job:result()
  if not result then
    return nil
  end

  local hash_binary
  if vim.fn.has("win32") == 1 then
    hash_binary = ""
    for _, line in ipairs(result) do
      if line and line ~= "" then
        hash_binary = hash_binary .. line
      end
    end
  else
    hash_binary = table.concat(result or {}, "")
  end

  if not hash_binary or hash_binary == "" then
    return nil
  end
  return hash_binary
end

---SHA256 hash using vim.fn.sha256 (returns binary)
---@param input string
---@return string|nil
function M.sha256_binary_vimfn(input)
  if vim.fn.exists("*sha256") ~= 1 then
    return nil
  end
  local ok, hash_hex = pcall(vim.fn.sha256, input)
  if not ok or not hash_hex or hash_hex == "" then
    return nil
  end
  return M.hex_to_binary(hash_hex)
end

---Get a temporary file path (cross-platform)
---@return string
function M.get_temp_file()
  local tmp_file = os.tmpname()
  if vim.fn.has("win32") == 1 then
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "."
    if not tmp_file:match("[\\/]") then
      tmp_file = temp_dir .. "\\" .. tmp_file
    end
  end
  return tmp_file
end

---Generate SHA256 hash in base64url format for PKCE (cross-platform)
---@param input string
---@return string|nil
function M.sha256_base64url(input)
  local hash_binary = nil

  -- Try OpenSSL with temp file approach (more reliable)
  if vim.fn.executable("openssl") == 1 then
    local tmp_file = M.get_temp_file()
    local f = io.open(tmp_file, "wb")
    if f then
      f:write(input)
      f:close()

      local result
      if vim.fn.has("win32") == 1 then
        local ps_exe = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
        local script = string.format(
          "$bytes = [System.IO.File]::ReadAllBytes('%s'); "
            .. "$hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes); "
            .. "[System.Convert]::ToBase64String($hash)",
          tmp_file:gsub("'", "''")
        )
        result = vim.fn.system({ ps_exe, "-NoProfile", "-Command", script })
      else
        result = vim.fn.system({ "openssl", "dgst", "-sha256", "-binary", tmp_file })
        if vim.v.shell_error == 0 and result then
          result = vim.base64.encode(result)
        end
      end

      os.remove(tmp_file)

      if vim.v.shell_error == 0 and result and result ~= "" then
        local base64 = M.trim(result)
        return base64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
      end
    end
  end

  -- Fallback to plenary Job or vim.fn.sha256
  hash_binary = M.sha256_binary_openssl(input) or M.sha256_binary_vimfn(input)
  if not hash_binary then
    return nil
  end

  local base64 = vim.base64.encode(hash_binary)
  return base64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

---Generate random string for PKCE
---@param length number
---@return string|nil
function M.generate_random_string(length)
  -- Try openssl for reliable random generation
  if vim.fn.executable("openssl") == 1 then
    local result = vim.fn.system({ "openssl", "rand", "-base64", tostring(math.ceil(length * 3 / 4)) })
    if vim.v.shell_error == 0 and result then
      local safe = M.trim(result):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
      if #safe >= length then
        return safe:sub(1, length)
      end
    end
  end

  -- Fallback to secure_random_bytes
  local bytes = M.secure_random_bytes(length)
  if not bytes then
    return nil
  end

  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  local result = {}
  for i = 1, length do
    local byte = bytes:byte(i)
    local rand_index = (byte % #chars) + 1
    result[i] = chars:sub(rand_index, rand_index)
  end
  return table.concat(result)
end

---Generate PKCE code verifier and challenge
---@param length? number Verifier length (default 64)
---@return { verifier: string, challenge: string }|nil
function M.generate_pkce(length)
  length = length or 64
  local verifier = M.generate_random_string(length)
  if not verifier then
    return nil
  end

  local challenge = M.sha256_base64url(verifier)
  if not challenge then
    return nil
  end

  return {
    verifier = verifier,
    challenge = challenge,
  }
end

---Generate random state for OAuth
---@return string
function M.generate_state()
  local bytes = M.secure_random_bytes(16)
  if bytes then
    local hex = {}
    for i = 1, #bytes do
      hex[i] = string.format("%02x", bytes:byte(i))
    end
    return table.concat(hex)
  end
  return M.generate_random_string(32) or ""
end

---Find data path for storing OAuth tokens
---@param env_var? string Optional environment variable to check first
---@return string|nil
function M.find_data_path(env_var)
  if env_var then
    local env_path = os.getenv(env_var)
    if env_path and vim.fn.isdirectory(vim.fs.dirname(env_path)) > 0 then
      return vim.fs.dirname(env_path)
    end
  end

  local nvim_data = vim.fn.stdpath("data")
  if nvim_data and vim.fn.isdirectory(nvim_data) > 0 then
    return nvim_data
  end

  return nil
end

---Get token file path
---@param filename string Token file name
---@param env_var? string Optional environment variable to check
---@return string|nil
function M.get_token_file_path(filename, env_var)
  local data_path = M.find_data_path(env_var)
  if not data_path then
    return nil
  end

  local path_sep = package.config:sub(1, 1)
  return data_path .. path_sep .. filename
end

---Load JSON data from file
---@param filepath string
---@return table|nil
function M.load_json_file(filepath)
  if not filepath or vim.fn.filereadable(filepath) == 0 then
    return nil
  end

  local success, content = pcall(vim.fn.readfile, filepath)
  if not success or not content or #content == 0 then
    return nil
  end

  local decode_success, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if decode_success and data then
    return data
  end

  return nil
end

---Save JSON data to file
---@param filepath string
---@param data table
---@return boolean
function M.save_json_file(filepath, data)
  if not filepath then
    return false
  end

  local success, json_data = pcall(vim.json.encode, data)
  if not success then
    return false
  end

  local write_success = pcall(function()
    if vim.fn.has("win32") == 1 then
      vim.fn.writefile(vim.split(json_data, "\n", { plain = true }), filepath, "b")
    else
      vim.fn.writefile({ json_data }, filepath)
    end
  end)

  return write_success
end

---Open URL in default browser (cross-platform)
---@param url string
---@return boolean success
function M.open_url(url)
  local success = false

  if vim.fn.has("mac") == 1 then
    vim.fn.system({ "open", url })
    success = vim.v.shell_error == 0
  elseif vim.fn.has("win32") == 1 then
    vim.fn.system({ "rundll32", "url.dll,FileProtocolHandler", url })
    success = vim.v.shell_error == 0
    if not success then
      local ps_exe = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
      vim.fn.system({ ps_exe, "-NoProfile", "-Command", "Start-Process", url })
      success = vim.v.shell_error == 0
    end
  elseif vim.fn.has("unix") == 1 then
    local openers = { "xdg-open", "gnome-open", "kde-open", "wslview" }
    for _, opener in ipairs(openers) do
      if vim.fn.executable(opener) == 1 then
        vim.fn.system({ opener, url })
        success = vim.v.shell_error == 0
        if success then
          break
        end
      end
    end
  end

  return success
end

---Start local HTTP server for OAuth callback
---@param port number
---@param callback_path string Path to match (e.g., "/oauth2callback")
---@param timeout_ms? number Timeout in milliseconds (default 5 minutes)
---@param success_html string HTML to return on success
---@param callback function(code: string|nil, error: string|nil, state: string|nil)
function M.start_oauth_server(port, callback_path, timeout_ms, success_html, callback)
  timeout_ms = timeout_ms or (5 * 60 * 1000)

  local server = uv.new_tcp()
  if not server then
    callback(nil, "Failed to create TCP server")
    return
  end

  local bind_ok, bind_err = server:bind("127.0.0.1", port)
  if not bind_ok then
    server:close()
    callback(nil, "Failed to bind to port " .. port .. ": " .. (bind_err or "unknown"))
    return
  end

  local listen_ok, listen_err = server:listen(128, function(err)
    if err then
      return
    end

    local client = uv.new_tcp()
    server:accept(client)

    local request_data = ""

    client:read_start(function(read_err, chunk)
      if read_err then
        client:close()
        return
      end

      if chunk then
        request_data = request_data .. chunk

        if string.find(request_data, "\r\n\r\n") then
          local request_line = string.match(request_data, "^([^\r\n]+)")
          local path = string.match(request_line or "", "GET ([^ ]+)")

          -- Escape special pattern characters in callback_path
          local escaped_path = callback_path:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")

          if path and string.find(path, escaped_path) then
            local query = string.match(path, "%?(.+)$")
            local params = M.parse_query_string(query)

            local response = "HTTP/1.1 200 OK\r\n"
              .. "Content-Type: text/html; charset=utf-8\r\n"
              .. "Content-Length: "
              .. #success_html
              .. "\r\n"
              .. "Connection: close\r\n"
              .. "\r\n"
              .. success_html

            client:write(response, function()
              client:shutdown()
              client:close()
              server:close()

              vim.schedule(function()
                if params.error then
                  callback(nil, "OAuth error: " .. (params.error_description or params.error), nil)
                elseif params.code then
                  callback(params.code, nil, params.state)
                else
                  callback(nil, "No authorization code received", nil)
                end
              end)
            end)
          else
            local not_found = "HTTP/1.1 404 Not Found\r\n"
              .. "Content-Type: text/plain\r\n"
              .. "Content-Length: 9\r\n"
              .. "Connection: close\r\n"
              .. "\r\n"
              .. "Not found"
            client:write(not_found, function()
              client:shutdown()
              client:close()
            end)
          end
        end
      else
        client:close()
      end
    end)
  end)

  if not listen_ok then
    server:close()
    callback(nil, "Failed to start server: " .. (listen_err or "unknown"))
    return
  end

  -- Set timeout
  local timeout = uv.new_timer()
  timeout:start(timeout_ms, 0, function()
    if not server:is_closing() then
      server:close()
      vim.schedule(function()
        callback(nil, "OAuth timeout - no callback received")
      end)
    end
    timeout:close()
  end)
end

---Base64 URL decode (for JWT)
---@param input string
---@return string|nil
function M.base64url_decode(input)
  if not input then
    return nil
  end
  -- Convert base64url to base64
  local base64 = input:gsub("-", "+"):gsub("_", "/")
  -- Add padding if necessary
  local padding = 4 - (#base64 % 4)
  if padding ~= 4 then
    base64 = base64 .. string.rep("=", padding)
  end
  local ok, decoded = pcall(vim.base64.decode, base64)
  if ok then
    return decoded
  end
  return nil
end

---Decode JWT token to extract payload
---@param token string
---@return table|nil
function M.decode_jwt(token)
  if not token or token == "" then
    return nil
  end
  local parts = vim.split(token, ".", { plain = true })
  if #parts ~= 3 then
    return nil
  end
  local payload = M.base64url_decode(parts[2])
  if not payload then
    return nil
  end
  local ok, data = pcall(vim.json.decode, payload)
  if ok and data then
    return data
  end
  return nil
end

---Check if access token is expired
---@param expires number|nil Token expiration timestamp in milliseconds
---@param buffer_ms? number Buffer time in milliseconds (default 60000)
---@return boolean
function M.is_token_expired(expires, buffer_ms)
  if not expires then
    return true
  end
  buffer_ms = buffer_ms or 60000
  local now_ms = os.time() * 1000
  return expires <= now_ms + buffer_ms
end

return M
