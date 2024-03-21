-- first line is type
local function get_code_blocks()
  local start_no = vim.fn.search('```', 'cnWb')
  local end_no = vim.fn.search('```', 'cnW')
  if start_no == 0 or end_no == 0 or start_no == end_no then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_no - 1, end_no - 1, true)
  lines[1] = lines[1]:sub(4, -1)
  return lines
end

local function envsubst(str)
  return str:gsub("%$(%b{})", function(var)
    local envVar = var:sub(2, -2)
    return vim.env[envVar] or ""
  end)
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

local function har2curl(lines, index)
  local method = ''
  local path = ''
  local headers = ''
  local body = ''
  local url = ''
  local header_end = false
  for i = index, #lines do
    local line = envsubst(lines[i])
    if method == '' then
      if startsWithHttpMethod(line) then
        method, path = line:match("(%S+)%s+(%S+)")
        url = path:sub(1, 1) == '/' and '' or path
      else
        if startsWith(line, 'export') then
          local equalsPos = string.find(line, '=')
          if equalsPos then
            local key = string.sub(line, 8, equalsPos - 1)
            local val = string.sub(line, equalsPos + 1)
            if key then
              vim.env[key] = val
            end
          end
        end
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
              if port == '443' then
                url = 'https://' .. hostname .. path
              else
                url = 'http://' .. hostname .. ':' .. port .. path
              end
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

  local curl_command = "curl -s -S -X " .. method .. headers .. " '" .. url .. "'"
  if body ~= "" then
    curl_command = curl_command .. " -d '" .. body .. "'"
  end
  return curl_command
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

local function cmd()
  local line = vim.fn.getline('.')
  if vim.bo.filetype == 'markdown' then
    local lines = get_code_blocks()
    if lines ~= nil then
      if lines[1] == 'http' then
        return har2curl(lines, 2)
      end
      return table.concat(lines, '\n', 2)
    end
  elseif vim.bo.filetype == 'go' then
    local funcName = string.match(line, "^func%s+Test([%w_]+)%(%w+%s*%*?%w+%.?%w*%)%s*%{")
    if funcName then
      return 'go test -timeout 30s -run ^Test' .. funcName .. '$ ' .. getGOPkg()
    end
  end
  return line
end

local function setup()
end

return {
  setup = setup,
  cmd = cmd,
}
