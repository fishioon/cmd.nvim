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

local function har2curl(lines, index)
  local method, path = lines[index]:match("(%S+)%s+(%S+)")
  local headers = ''
  local body = ''
  local url = path:sub(1, 1) == '/' and '' or path
  local header_end = false
  for i = index + 1, #lines do
    local line = lines[i]
    if not header_end then
      if line == '' then
        header_end = true
      else
        headers = headers .. ' -H "' .. line .. '"'
        if url == '' then
          local hostname, port = line:lower():match("host:%s*(.-):?(%d*)$")
          if port == '443' then
            url = 'https://' .. hostname .. path
          else
            url = 'http://' .. hostname .. ':' .. port .. path
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

  local curl_command = "curl -s -S -X " .. method .. headers .. " '" .. url .. "'"
  if body ~= "" then
    curl_command = curl_command .. " -d '" .. body .. "'"
  end
  return curl_command
end

local function cmd()
  if vim.bo.filetype == 'markdown' then
    local lines = get_code_blocks()
    if lines ~= nil then
      if lines[1] == 'http' then
        return har2curl(lines, 2)
      end
      return table.concat(lines, '\n', 2)
    end
  end
  return vim.fn.getline('.')
end

local function setup()
end

return {
  setup = setup,
  cmd = cmd,
}
