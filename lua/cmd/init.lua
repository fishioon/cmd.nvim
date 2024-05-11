local curl_command = 'curl -s -S {input}'
local env = {}

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
        env[key] = val
      end
    end
  end
  return line
end

local function envsubst(str)
  return str:gsub("%$(%b{})", function(var)
    local envVar = var:sub(2, -2)
    return env[envVar] or ""
  end)
end

local function har2curl(lines)
  local method = ''
  local path = ''
  local headers = ''
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
        if line == '' then
          header_end = true
        else
          headers = headers .. ' -H "' .. line .. '"'
          if url == '' then
            if startsWith(line, 'host') or startsWith(line, 'Host') then
              local hostname, port = line:lower():match("host:%s*(.-):?(%d*)$")
              if port == '' then
                port = '80'
              end
              local protocol = port == '443' and 'https://' or 'http://'
              url = protocol .. hostname .. ':' .. port .. path
            end
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
  if method == '' or url == '' then
    error("invalid http request")
  end

  local curl_input = '-X ' .. method .. headers .. " '" .. url .. "'"
  if body ~= "" then
    curl_input = curl_input .. " -d '" .. body .. "'"
  end

  local curl = env.curl and env.curl or curl_command
  return string.gsub(curl, "{input}", curl_input)
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

local function loadEnv()
  local start_no = vim.fn.search('```env', 'n')
  local end_no = vim.fn.search('```', 'n')
  if start_no == 0 or end_no == 0 or start_no == end_no then
    return
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
end

local function cmd()
  local line = vim.fn.getline('.')
  if vim.bo.filetype == 'markdown' then
    loadEnv()
    local kind, lines = get_code_blocks()
    if kind and lines then
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
      return 'go test -timeout 30s -run ^Test' .. funcName .. '$ ' .. getGOPkg()
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
