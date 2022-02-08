VERSION = "1.1.0"

-- micro
local micro = import("micro")
local config = import("micro/config")
local util = import("micro/util")
local shell = import("micro/shell")
-- golang
local filepath = import("filepath")
local http = import("http")
local ioutil = import("io/ioutil")
local os2 = import("os")
local runtime = import("runtime")
-- wakatime
local userAgent = "micro/" .. util.SemVersion:String() .. " micro-wakatime/" .. VERSION
local lastFile = ""
local lastHeartbeat = 0

function init()
    config.MakeCommand("wakatime.apikey", promptForApiKey, config.NoComplete)

    micro.InfoBar():Message("WakaTime initializing...")
    micro.Log("initializing WakaTime v" .. VERSION)

    checkCli()
    checkApiKey()
end

function postinit()
    micro.InfoBar():Message("WakaTime initialized")
    micro.Log("WakaTime initialized")
end

function checkCli()
    if not cliUpToDate() then
        downloadCli()
    end
end

function checkApiKey()
    if not hasApiKey() then
        promptForApiKey()
    end
end

function hasApiKey()
    return getApiKey() ~= nil
end

function getApiKey()
    return getSetting("settings", "api_key")
end

function getConfigFile()
    return filepath.Join(os2.UserHomeDir(), ".wakatime.cfg")
end

function getSetting(section, key)
    config, err = ioutil.ReadFile(getConfigFile())
    if err ~= nil then
        micro.InfoBar():Message("failed reading ~/.wakatime.cfg")
        micro.Log("failed reading ~/.wakatime.cfg")
        micro.Log(err)
    end

    lines = util.String(config)
    currentSection = ""

    for line in lines:gmatch("[^\r\n]+") do
        line = string.trim(line)
        if string.starts(line, "[") and string.ends(line, "]") then
            currentSection = string.lower(string.sub(line, 2, string.len(line) -1))
        elseif currentSection == section then
            parts = string.split(line, "=")
            currentKey = string.trim(parts[1])
            if currentKey == key then
                return string.trim(parts[2])
            end
        end
    end

    return ""
end

function setSetting(section, key, value)
    config, err = ioutil.ReadFile(getConfigFile())
    if err ~= nil then
        micro.InfoBar():Message("failed reading ~/.wakatime.cfg")
        micro.Log("failed reading ~/.wakatime.cfg")
        micro.Log(err)
        return
    end

    contents = {}
    currentSection = ""
    lines = util.String(config)
    found = false

    for line in lines:gmatch("[^\r\n]+") do
        line = string.trim(line)
        if string.starts(line, "[") and string.ends(line, "]") then
            if currentSection == section and not found then
                table.insert(contents, key .. " = " .. value)
                found = true
            end
            
            currentSection = string.lower(string.sub(line, 2, string.len(line) -1))
            table.insert(contents, string.rtrim(line))
        elseif currentSection == section then
            parts = string.split(line, "=")
            currentKey = string.trim(parts[1])
            if currentKey == key then
                if not found then
                    table.insert(contents, key .. " = " .. value)
                    found = true
                end
            else
                table.insert(contents, string.rtrim(line))
            end
        else
            table.insert(contents, string.rtrim(line))
        end
    end

    if not found then
        if currentSection ~= section then 
            table.insert(contents, "[" .. section .. "]")
        end

        table.insert(contents, key .. " = " .. value)
    end

    _, err = ioutil.WriteFile(getConfigFile(), table.concat(contents, "\n"), 0700)
    if err ~= nil then
        micro.InfoBar():Message("failed saving ~/.wakatime.cfg")
        micro.Log("failed saving ~/.wakatime.cfg")
        micro.Log(err)
        return
    end

    micro.Log("~/.wakatime.cfg successfully saved")
end

function downloadCli()
    local io = import("io")
    local zip = import("archive/zip")

    local url = "https://github.com/wakatime/wakatime-cli/releases/latest/download/wakatime-cli-linux-arm.zip"
    local zipFile = filepath.Join(resourcesFolder(), "wakatime-cli-linux-arm.zip")

    micro.InfoBar():Message("downloading wakatime-cli-linux-arm...")
    micro.Log("downloading wakatime-cli-linux-arm from " .. url)

    _, err = os2.Stat(resourcesFolder())
    if os2.IsNotExist(err) then
        os.execute("mkdir " .. resourcesFolder())
    end
    
    -- download cli
    local res, err = http.Get(url)
    if err ~= nil then
        micro.InfoBar():Message("error downloading wakatime-cli-linux-arm.zip")
        micro.Log("error downloading wakatime-cli-linux-arm.zip")
        micro.Log(err)
        return
    end

    out, err = os2.Create(zipFile)
    if err ~= nil then
        micro.InfoBar():Message("error creating new wakatime-cli-linux-arm.zip")
        micro.Log("error creating new wakatime-cli-linux-arm.zip")
        micro.Log(err)
        return
    end

    _, err = io.Copy(out, res.Body)
    if err ~= nil then
        micro.InfoBar():Message("error saving wakatime-cli-linux-arm.zip")
        micro.Log("error saving wakatime-cli-linux-arm.zip")
        micro.Log(err)
        return 
    end

    err = util.Unzip(zipFile, resourcesFolder())
    os2.Remove(zipFile)

    if err ~= nil then
        micro.InfoBar():Message("failed to unzip wakatime-cli-linux-arm.zip")
        micro.Log("failed to unzip wakatime-cli-linux-arm.zip")
        micro.Log(err)
        return
    end
end

function resourcesFolder()
    return filepath.Join(os2.UserHomeDir(), ".wakatime")
end

function cliPath()
    return filepath.Join(resourcesFolder(), "wakatime-cli-linux-arm")
end

function cliExists()
    local _, err = os2.Stat(cliPath())

    if os2.IsNotExist(err) then
        micro.Log("cli (" .. cliPath() ..") does not exist")
        return false
    end

    return true
end

local function kind_of(obj)
    if type(obj) ~= 'table' then return type(obj) end
    local i = 1
    for _ in pairs(obj) do
        if obj[i] ~= nil then i = i + 1 else return 'table' end
    end
    if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
    local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
    local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
    for i, c in ipairs(in_char) do
        s = s:gsub(c, '\\' .. out_char[i])
    end
    return s
end
-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
    pos = pos + #str:match('^%s*', pos)
    if str:sub(pos, pos) ~= delim then
        if err_if_missing then
            error('Expected ' .. delim .. ' near position ' .. pos)
        end
        return pos, false
    end
    return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
    val = val or ''
    local early_end_error = 'End of input found while parsing string.'
    if pos > #str then error(early_end_error) end
    local c = str:sub(pos, pos)
    if c == '"'  then return val, pos + 1 end
    if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
    -- We must have a \ character.
    local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
    local nextc = str:sub(pos + 1, pos + 1)
    if not nextc then error(early_end_error) end
    return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
    local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    local val = tonumber(num_str)
    if not val then error('Error parsing number at position ' .. pos .. '.') end
    return val, pos + #num_str
end

json_null = {}  -- This is a one-off table to represent the null value.

function parse_json(str, pos, end_delim)
    pos = pos or 1
    if pos > #str then error('Reached unexpected end of input.') end
    local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
    local first = str:sub(pos, pos)
    if first == '{' then  -- Parse an object.
        local obj, key, delim_found = {}, true, true
        pos = pos + 1
        while true do
            key, pos = parse_json(str, pos, '}')
            if key == nil then return obj, pos end
            if not delim_found then error('Comma missing between object items.') end
            pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
            obj[key], pos = parse_json(str, pos)
            pos, delim_found = skip_delim(str, pos, ',')
        end
    elseif first == '[' then  -- Parse an array.
        local arr, val, delim_found = {}, true, true
        pos = pos + 1
        while true do
            val, pos = parse_json(str, pos, ']')
            if val == nil then return arr, pos end
            if not delim_found then error('Comma missing between array items.') end
            arr[#arr + 1] = val
            pos, delim_found = skip_delim(str, pos, ',')
        end
    elseif first == '"' then  -- Parse a string.
        return parse_str_val(str, pos + 1)
    elseif first == '-' or first:match('%d') then  -- Parse a number.
        return parse_num_val(str, pos)
    elseif first == end_delim then  -- End of an object or array.
        return nil, pos + 1
    else  -- Parse true, false, or null.
        local literals = {['true'] = true, ['false'] = false, ['null'] = json_null}
        for lit_str, lit_val in pairs(literals) do
            local lit_end = pos + #lit_str - 1
            if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
        end
        local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
        error('Invalid json syntax starting at ' .. pos_info_str)
    end
end

function cliUpToDate()
    if not cliExists() then
        return false
    end

    local ioutil = import("ioutil")
    local fmt = import("fmt")

    -- get current version from installed cli
    local currentVersion, err = shell.ExecCommand(cliPath(), "--version")
    if err ~= nil then
        micro.InfoBar():Message("failed to determine current cli version")
        micro.Log("failed to determine current cli version")
        micro.Log(err)
        return true
    end

    micro.Log("Current wakatime-cli version is " .. currentVersion)
    micro.Log("Checking for updates to wakatime-cli...")

    local url = "https://api.github.com/repos/wakatime/wakatime-cli/releases/latest"
    -- read version from GitHub
    local res, err = http.Get(url)
    if err ~= nil then
        micro.InfoBar():Message("error retrieving wakatime-cli version from GitHub")
        micro.Log("error retrieving wakatime-cli version from GitHub")
        micro.Log(err)
        return true
    end

    body, err = ioutil.ReadAll(res.Body)
    if err ~= nil then
        micro.InfoBar():Message("error reading all bytes from response body")
        micro.Log("error reading all bytes from response body")
        micro.Log(err)
        return true
    end

    micro.Log("Trying to parse JSON...")

    -- parse byte array to string
    latestVersion = parse_json(util.String(body))["name"]

    if string.gsub(latestVersion, "[\n\r]", "") == string.gsub(currentVersion, "[\n\r]", "") then
        micro.Log("wakatime-cli is up to date")
        return true
    end

    micro.Log("Found an updated wakatime-cli v" .. latestVersion)

    return false
end


function onSave(bp)
    onEvent(bp.buf.AbsPath, true)

    return true
end

function onSaveAll(bp)
    onEvent(bp.buf.AbsPath, true)

    return true
end

function onSaveAs(bp)
    onEvent(bp.buf.AbsPath, true)

    return true
end

function onOpenFile(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onPaste(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectAll(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onDeleteLine(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorUp(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorDown(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorPageUp(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorPageDown(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorLeft(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorRight(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorStart(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onCursorEnd(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectToStart(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectToEnd(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectUp(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectDown(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectLeft(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectRight(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectToStartOfText(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectToStartOfTextToggle(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onWordRight(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onWordLeft(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectWordRight(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onSelectWordLeft(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onMoveLinesUp(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onMoveLinesDown(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onScrollUp(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function onScrollDown(bp)
    onEvent(bp.buf.AbsPath, false)

    return true
end

function enoughTimePassed(time)
    return lastHeartbeat + 120000 < time
end

function onEvent(file, isWrite)
    time = os.time()
    if isWrite or enoughTimePassed(time) or lastFile ~= file then
        sendHeartbeat(file, isWrite)
        lastFile = file
        lastHeartbeat = time
    end
end

function sendHeartbeat(file, isWrite)
    micro.Log("Sending heartbeat")

    local isDebugEnabled = getSetting("settings", "debug"):lower()
    local args = {"--entity", file, "--plugin", userAgent}
    
    if isWrite then
        table.insert(args, "--write")
    end

    if isDebugEnabled then
        table.insert(args, "--verbose")
    end

    -- run it in a thread
    shell.JobSpawn(cliPath(), args, nil, sendHeartbeatStdErr, sendHeartbeatExit)
end

function sendHeartbeatStdErr(err)
    micro.Log(err)
    micro.Log("Check your ~/.wakatime.log file for more details.")
end

function sendHeartbeatExit(out, args)
    micro.Log("Last heartbeat sent " .. os.date("%c"))
end

function promptForApiKey()
    micro.InfoBar():Prompt("API Key: ", getApiKey(), "api_key", function(input) 
        return
    end, function(input, canceled)
        if not canceled then
            if isValidApiKey(input) then
                setSetting("settings", "api_key", input)
            else
                micro.Log("Api Key not valid!")
            end
        end
    end)
end

function isValidApiKey(key)
    if key == "" then
        return false
    end

    local regexp = import("regexp")

    matched, _ = regexp.MatchString("(?i)^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$", key)

    return matched
end

function ternary (cond, T, F)
    if cond then return T else return F end
end

function string.starts(str, start)
    return str:sub(1,string.len(start)) == start
end

function string.ends(str, ending)
    return ending == "" or str:sub(-string.len(ending)) == ending
end

function string.trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

function string.rtrim(str)
    local n = #str
    while n > 0 and str:find("^%s", n) do n = n - 1 end
    return str:sub(1, n)
end

function string.split(str, delimiter)
    t = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(t, match);
    end
    return t
end
