require "cosy.lang.cosy"
js.global.cosy = cosy

local observed = require "cosy.lang.view.observed"
observed [#observed + 1] = require "cosy.lang.view.update"
cosy = observed (cosy)

local sha1      = require "sha1"
local json      = require "dkjson"

local seq    = require "cosy.lang.iterators" . seq
local set    = require "cosy.lang.iterators" . set
local map    = require "cosy.lang.iterators" . map
local raw    = require "cosy.lang.data" . raw
local tags   = require "cosy.lang.tags"
local update = require "cosy.lang.view.update"
local type   = require "cosy.util.type"

local WS       = tags.WS
local RESOURCE = tags.RESOURCE
local UPDATES  = tags.UPDATES

local function connect (parameters)
  local token    = parameters.token
  local resource = parameters.resource
  local editor   = parameters.editor
  local ws       = js.global:websocket (editor)
  local result   = {
    [RESOURCE] = resource,
    [WS      ] = ws,
    [UPDATES ] = {},
  }
  ws.token   = token
  function ws:onopen ()
    ws:request {
      action   = "set-resource",
      token    = token,
      resource = resource,
    }
  end
  function ws:onclose ()
    result [WS] = nil
  end
  function ws:onmessage (event)
    local message = event.data
    print (message)
    if not message then
      return
    end
    local command = json.decode (message)
    if command.action == "update" then
      update.from_patch = true
      for patch in seq (command.patches) do
        print ("Applying patch " .. tostring (patch.data))
        pcall (loadstring, patch.data)
      end
      update.from_patch = nil
    else
      -- do nothing
    end
  end
  function ws:onerror ()
    ws:close ()
  end
  function ws:request (command)
    local str = json.encode (command)
    command.request_id = sha1 (tostring (os.time()) .. "+" .. str)
    command.token = ws.token
    if ws.readyState == 1 then
      ws:send (json.encode (command))
    end
  end
  function ws:patch (str)
    local command = {
      action = "add-patch",
      data   = str,
    }
    local str = json.encode (command)
    command.request_id = sha1 (tostring (os.time()) .. "+" .. str)
    command.token = ws.token
    if ws.readyState == 1 then
      ws:send (json.encode (command))
    end
  end
  cosy [resource] = result
  return cosy [resource]
end

function window:count (x)
  return #x
end

function window:id (x)
  if type (x) == "table" then
    local mt = getmetatable (x)
    setmetatable (x, nil)
    local result = tostring (x)
    setmetatable (x, mt)
    return result
  else
    return tostring (x)
  end
end

function window:keys (x)
  local result = {}
  for key, _ in pairs (x) do
    result [#result + 1] = key
  end
  return result
end

function window:elements (model)
  local TYPE = tags.TYPE
  local function set_of (e)
    local result = {}
    for _, x in map (e) do
      if type (x) . table and x [TYPE] then
        result [raw (x)] = true
      elseif type (x) . table then
        for y in seq (set_of (x)) do
          result [y] = true
        end
      end
    end
    return result
  end
  local result = {}
  for x in set (set_of (model)) do
    result [#result + 1] = x
  end
  return result
end

function window:connect (editor, token, resource)
  return connect {
    editor   = editor,
    token    = token,
    resource = resource,
  }
end