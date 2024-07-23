local curl_command = 'curl -s -S {input}'
local local_env = {}

local function get_env(name, default_var)
  return local_env[name] or vim.env[name] or default_var
end

local function get_code_blocks()
  local start_no = vim.fn.search('```', 'cnWb')
  local end_no = vim.fn.search('```', 'cnW')
  if start_no == 0 or end_no == 0 or start_no == end_no then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_no - 1, end_no - 1, true)
  local kind = lines[1]:sub(4, -1)
  table.remove(lines, 1)
  return kind, lines
end

local function startsWith(str, substr)
  return string.sub(str, 1, string.len(substr)) == substr
end

local function startsWithHttpMethod(str)
  local httpMethods = { "POST", "GET", "PUT", "DELETE" }
  for _, method in ipairs(httpMethods) do
    if startsWith(str, method) then
      return true
    end
  end
  return false
end

local function handleExport(line)
  if startsWith(line, 'export') then
    local equalsPos = string.find(line, '=')
    if equalsPos then
      local key = string.sub(line, 8, equalsPos - 1)
      local val = string.sub(line, equalsPos + 1)
      if key then
        local_env[key] = val
      end
    end
  end
  return line
end

local function envsubst(str)
  local s = str:gsub("%$(%b{})", function(var)
    return get_env(var:sub(2, -2), '${' .. var .. '}')
  end)
  return s
end

local function parse_host(host)
  local hostname, port = host:gsub("^%s*(.-)%s*$", "%1"):match("([^:]+):?(%d*)")
  if port == "" then
    port = "80"
  end
  return hostname, port
end

local function har2curl(lines)
  local method = ''
  local path = ''
  local headers = ''
  local host = get_env('host', '')
  local body = ''
  local url = ''
  local header_end = false
  for i = 1, #lines do
    local line = lines[i]
    if method == '' then
      if startsWithHttpMethod(line) then
        method, path = line:match("(%S+)%s+(%S+)")
        url = path:sub(1, 1) == '/' and '' or path
      end
    else
      if not header_end then
        if line == '' or line == '{' then
          header_end = true
          body = line
        else
          if startsWith(line, 'host:') or startsWith(line, 'Host:') then
            host = line:sub(6)
          else
            headers = headers .. ' -H "' .. line .. '"'
          end
        end
      else
        if body == '' then
          body = line
        else
          body = body .. '\n' .. line
        end
      end
    end
  end
  if url == '' and host ~= '' and path ~= '' then
    local hostname, port = parse_host(host)
    local protocol = port == '443' and 'https://' or 'http://'
    url = protocol .. hostname
    if port ~= '443' and port ~= '80' then
      url = url .. ':' .. port
    end
    url = url .. path
  end
  if method == '' or url == '' then
    error("invalid http request")
  end

  local curl_input = '-X ' .. method .. headers .. " '" .. url .. "'"
  if body ~= "" then
    curl_input = curl_input .. " -d '" .. body .. "'"
  end

  return string.gsub(get_env('curl', curl_command), "{input}", curl_input)
end

local function getGOPkg()
  local file = io.open("go.mod", "r")
  if file then
    local content = file:read("*all")
    file:close()
    local module = string.match(content, "module%s+(%S+)")
    if module then
      local pkg = string.sub(vim.api.nvim_buf_get_name(0), #vim.loop.cwd() + 1)
      local sub = string.match(pkg, "(.-)/[^/]*$")
      return module .. sub
    end
  end
  return ""
end

local function handleEnv(lines)
  for i = 1, #lines do
    lines[i] = handleExport(envsubst(lines[i]))
  end
  return lines
end

local function loadEnv(cursor)
  local env = {}
  local start_no = vim.fn.search('```env', 'bcW')
  local end_no = vim.fn.search('```', 'W')
  vim.fn.cursor(cursor)
  if start_no == 0 or end_no == 0 or start_no == end_no then
    return env
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_no, end_no - 1, true)
  for i = 1, #lines do
    local line = lines[i]
    local equalsPos = string.find(line, '=')
    if equalsPos then
      local key = string.sub(line, 1, equalsPos - 1)
      local val = string.sub(line, equalsPos + 1)
      if key then
        env[key] = val
      end
    end
  end
  return env
end

local function cmd()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.fn.getline('.')
  if vim.bo.filetype == 'markdown' then
    local_env = loadEnv(cursor)
    local kind, lines = get_code_blocks()
    if kind and #kind > 0 and lines then
      lines = handleEnv(lines)
      if kind == 'http' then
        return har2curl(lines)
      elseif kind == 'sh' then
        return table.concat(lines, '\n', 1)
      end
    end
  elseif vim.bo.filetype == 'go' then
    local funcName = string.match(line, "^func%s+Test([%w_]+)%(%w+%s*%*?%w+%.?%w*%)%s*%{")
    if funcName then
      return "go test -timeout 30s -run '^Test" .. funcName .. "$' " .. getGOPkg()
    end
  end
  return handleExport(envsubst(line))
end

local function setup()
end

return {
  setup = setup,
  cmd = cmd,
}
