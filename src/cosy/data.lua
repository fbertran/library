require "compat53"

local Repository = {}
local Proxy      = {}

local function make_tag (name)
  return setmetatable ({}, {
    __tostring = function () return name end
  })
end

Repository.__metatable = "cosy.data"
Proxy     .__metatable = "cosy.data.proxy"

local CURRENT    = make_tag "CURRENT"
local CONTENTS   = make_tag "CONTENTS"
local LINEARIZED = make_tag "LINEARIZED"
local OPTIONS    = make_tag "OPTIONS"
local REPOSITORY = make_tag "REPOSITORY"
local KEYS       = make_tag "KEYS"
local PROXIES    = make_tag "PROXIES"
local PARENT     = make_tag "PARENT"

Repository.VALUE    = "_"
Repository.DEPENDS  = "cosy:depends"
Repository.INHERITS = "cosy:inherits"
Repository.REFERS   = "cosy:refers"
Repository.RELATIVE = "cosy:relative"

local Options = {}

function Options.new ()
  return {
    filter   = nil,
    on_read  = nil,
    on_write = nil,
  }
end

function Options.wrap (options)
  return setmetatable ({
    [OPTIONS] = options,
    [CURRENT] = options,
  }, Options)
end

function Options.__index (options, key)
  local found = options [CURRENT] [key]
  if type (found) ~= "table" then
    return found
  else
    return setmetatable ({
      [OPTIONS] = options [OPTIONS],
      [CURRENT] = found,
    }, Options)
  end
end

function Options.__newindex (options, key, value)
  local found = options [CURRENT] [key]
  options [CURRENT] [key] = value
  local err = Options.check (options [OPTIONS])
  if err then
    options [CURRENT] [key] = found
    error (err)
  end
end

function Options.check (options)
  local function is_function (f)
    return type (f) == "function"
        or type (f) == "thread"
        or (    type (f) == "table"
            and getmetatable (f) ~= nil
            and getmetatable (f).__call ~= nil)
  end
  for key, value in pairs (options) do
    if key == "filter" then
      if not is_function (value) then
        return "options.filter must be a function"
      end
    elseif key == "on_read" then
      if not is_function (value) then
        return "options.on_read must be a function"
      end
    elseif key == "on_write" then
      if not is_function (value) then
        return "options.on_write must be a function"
      end
    else
      error ("unknown option: " .. tostring (key))
    end
  end
end

function Repository.new ()
  local repository = setmetatable ({
    [CONTENTS  ] = {},
    [LINEARIZED] = {},
    [OPTIONS   ] = Options.new (),
    [PROXIES   ] = false,
  }, Repository)
  repository [PROXIES] = setmetatable ({
    [REPOSITORY] = repository,
    [KEYS      ] = {},
    [PROXIES   ] = setmetatable ({}, { __mode = "kv" }),
    [PARENT    ] = false,
  }, Proxy)
  return repository
end

function Repository.__index (repository, key)
  return repository [PROXIES] [key]
end

function Repository.__newindex (repository, key, value)
  repository [PROXIES] [key] = Repository.import (key, value)
end

function Repository.raw (repository)
  return repository [CONTENTS]
end

function Repository.options (repository)
  return Options.wrap (repository [OPTIONS])
end

function Repository.path (proxy)
  return proxy [KEYS]
end

function Repository.delete (proxy)
  local repository = proxy [REPOSITORY]
  local keys       = proxy [KEYS]
  local data       = repository
  for i = 1, #keys-1 do
    data = data [keys [i]]
  end
  data [keys [#keys]] = nil
end

function Repository.import (key, value, within)
  if type (value) ~= "table" then
    return value
  end
  if key == Repository.DEPENDS then
    within = Repository.DEPENDS
  elseif key == Repository.INHERITS then
    within = Repository.INHERITS
  elseif key == Repository.REFERS then
    within = Repository.REFERS
  end
  if getmetatable (value) == Proxy.__metatable then
    if within == Repository.DEPENDS then
      value = value [KEYS] [1]
    elseif within == Repository.INHERITS 
        or within == Repository.REFERS then
      local keys = value [KEYS]
      local path = {}
      for i = 2, #keys do
        path [i-1] = keys [i]
      end
      value = path
    else
      local keys = value [KEYS]
      local path = {}
      for i = 2, #keys do
        path [i-1] = keys [i]
      end
      value = {
        [Repository.REFERS ] = path,
      }
    end
    return value
  end
  local import = Repository.import
  for k, v in pairs (value) do
    value [k] = import (k, v, within)
  end
  return value
end

function Repository.linearize (proxy, parents)
  local repository = proxy [REPOSITORY]
  local cache      = repository [LINEARIZED]
  if not cache [parents] then
    -- Store proxy -> result
    cache [parents] = setmetatable ({}, { __mode = "k" })
  end
  cache = cache [parents]
  local seen = {}
  local function linearize (t)
--    local identifier = Proxy.identifier (t)
    local cached = cache [t]
    if cached then
      return cached
    end
    if seen [t] then
      return {}
    end
    seen [t] = true
    -- Prepare:
    local depends = parents (t)
    local l, n = {}, {}
    if depends then
      depends = table.pack (table.unpack (depends))
      for i = 1, #depends do
        depends [i] = depends [i]
      end
      l [#l+1] = depends
      n [#n+1] = #depends
      for i = 1, #depends do
        local linearized = linearize (depends [i], seen)
        if #linearized ~= 0 then
          local ll = {}
          for j = 1, #linearized do
            local x = linearized [j]
            if x ~= t then
              ll [#ll+1] = x
            end
          end
          l [#l+1] = ll
          n [#n+1] = # (l [#l])
        end
      end
    end
    l [#l+1] = { t }
    n [#n+1] = 1
--[[
    do
      local dump = {}
      for i = 1, #l do
        local x = {}
        for j = 1, #(l [i]) do
          x [j] = tostring (l [i] [j])
        end
        dump [i] = "{ " .. table.concat (x, ", ") .. " }"
      end
      print ("l", table.concat (dump, ", "))
    end
--]]
    -- Compute tails:
    local tails = {}
    for i = 1, #l do
      local v = l [i]
      for j = 1, #v do
        local w   = v [j]
        tails [w] = (tails [w] or 0) + 1
      end
    end
--[[
    do
      local dump = {}
      for k, v in pairs (tails) do
        dump [#dump+1] = tostring (k) .. " = " .. tostring (v)
      end
      print ("tails", table.concat (dump, ", "))
    end
--]]
    -- Compute linearization:
    local result = {}
    while #l ~= 0 do
      for i = #l, 1, -1 do
        local vl, vn   = l [i], n [i]
        local first    = vl [vn]
        local first_id = first
        tails [first_id] = tails [first_id] - 1
      end
      local head
      for i = #l, 1, -1 do
        local vl, vn   = l [i], n [i]
        local first    = vl [vn]
        local first_id = first
        if tails [first_id] == 0 then
          head = first
          break
        end
      end
      if head == nil then
        error "Linearization failed"
      end
      result [#result + 1] = head
      for i = 1, #l do
        local vl, vn = l [i], n [i]
        local first  = vl [vn]
        if first == head then
          n [i] = n [i] - 1
        else
          local first_id = first
          tails [first_id] = tails [first_id] + 1
        end
      end
      local nl, nn = {}, {}
      for i = 1, #l do
        if n [i] ~= 0 then
          nl [#nl+1] = l [i]
          nn [#nn+1] = n [i]
        end
      end
      l, n = nl, nn
    end
    for i = 1, #result/2 do
      result [i], result [#result-i+1] = result [#result-i+1], result [i]
    end
    cache [t] = result
--[[
    do
      local dump = {}
      for i = 1, #result do
        dump [i] = tostring (result [i])
      end
      print ("result", table.concat (dump, ", "))
    end
--]]
    return result
  end
  return linearize (proxy)
end

--[[
function Proxy.identifier (t)
  local repository = t [REPOSITORY]
  local keys       = t [KEYS]
  local parts      = {}
  parts [1] = tostring (repository)
  for i = 1, #(keys) do
    local key = keys [i]
    parts [i+1] = type (key) .. ":" .. tostring (key)
  end
  return table.concat (parts, "|")
end
--]]

function Repository.depends (proxy)
  local repository = proxy [REPOSITORY]
  local keys       = proxy [KEYS      ]
  local contents   = repository [CONTENTS]
  assert (#keys == 1)
  local key        = keys [1]
  local data       = contents [key]
  if data == nil then
    return nil
  end
  local depends = data [Repository.DEPENDS]
  if depends == nil then
    return nil
  end
  depends = table.pack (table.unpack (depends))
  for i = 1, #depends do
    depends [i] = repository [depends [i]]
  end
  return depends
end

function Repository.parents (proxy)
  proxy = Proxy.dereference (proxy)
  local repository = proxy [REPOSITORY]
  local keys       = proxy [KEYS      ]
  local contents   = repository [CONTENTS]
  local root       = repository [keys [1]]
  local layers     = Repository.linearize (root, Repository.depends)
  local parents    = {}
  for i = 1, #layers do
    local layer = layers [i] [KEYS] [1]
    local data  = contents [layer]
    for j = 2, #keys do
      if type (data) == "table" then
        data = data [keys [j]]
      else
        data = nil
        break
      end
    end
    if type (data) == "table" then
      local inherits = data [Repository.INHERITS] or {}
      for k = 1, #inherits do
        local path    = inherits [k]
        local inherit = root
        for l = 1, #path do
          inherit = inherit [path [l]]
        end
        parents [#parents+1] = inherit
      end
    end
  end
  if #parents ~= 0 then
    return parents
  else
    return nil
  end
end

function Proxy.__index (proxy, key)
  if type (key) == "table" then
    error "Not implemented"
  end
  do
    local proxies = proxy [PROXIES]
    local found   = proxies [key]
    if found then
      return found
    end
  end
  local repository = proxy [REPOSITORY]
  local keys       = proxy [KEYS]
  if key ~= "_" then
    keys = table.pack (table.unpack (keys))
    keys [#keys+1] = key
    local result = setmetatable ({
      [REPOSITORY] = repository,
      [KEYS      ] = keys,
      [PROXIES   ] = setmetatable ({}, { __mode = "kv" }),
      [PARENT    ] = proxy,
    }, Proxy)
    proxy [PROXIES] [key] = result
    return result
  else
    proxy = Proxy.dereference (proxy)
    if proxy == nil then
      return nil
    end
    local keys       = proxy [KEYS]
    local contents   = repository [CONTENTS]
    local options    = repository [OPTIONS ]
    local filter     = options.filter
    local on_read    = options.on_read
    local root       = repository [keys [1]]
    local layers     = Repository.linearize (root, Repository.depends)
    if filter then
      options.filter  = nil
      options.on_read = nil
      local p = repository
      for i = 1, #keys do
        p = p [keys [i]]
        if not filter (p) then
          options.filter  = filter
          options.on_read = on_read
          return nil
        end
      end
      options.filter  = filter
      options.on_read = on_read
    end
    for i = #layers, 1, -1 do
      local layer = layers [i] [KEYS] [1]
      local data  = contents [layer]
      for j = 2, #keys do
        if type (data) ~= "table" then
          data = nil
          break
        end
        local key = keys [j]
        data = data [key]
        if data == nil then
          break
        end
        -- Special cases:
        if key == Repository.REFERS then
          assert (false)
        elseif key == Repository.INHERITS then
          -- TODO
          error "Not implemented"
        elseif key == Repository.DEPENDS then
          -- Do nothing
        end
      end
      if type (data) == "table" then
        data = data [Repository.VALUE]
      end
      if data ~= nil then
        if on_read then
          options.filter   = nil
          options.on_read  = nil
          on_read (proxy, data)
          options.filter   = filter
          options.on_read  = on_read
        end
        return data
      end
    end
    -- Search in parents:
    print ("inherits", root, root [REPOSITORY])
    local proxies = { root }
    local current = root
    for i = 2, #keys do
      current = current [keys [i]]
      proxies [#proxies+1] = current
    end
    for i = #proxies, 1, -1 do
      local proxy   = proxies [i]
      local parents = Repository.linearize (proxy, Repository.parents)
      for j = #parents-1, 1, -1 do
        local parent = parents [j]
        for k = i+1, #keys do
          parent = parent [keys [k]]
        end
        print ("looking in", parent)
        local result = parent._
        print ("result", result)
        if result then
          return result
        end
      end
    end
    return nil
  end
end

function Proxy.__call (proxy, n)
  for _ = 1, n or 1 do
    proxy = proxy [Repository.REFERS]
  end
  return proxy
end

function Proxy.dereference (proxy)
  local repository = proxy [REPOSITORY]
  local keys       = proxy [KEYS      ]
  local contents   = repository [CONTENTS]
  local root       = repository [keys [1]]
  local layers     = Repository.linearize (root, Repository.depends)
  while true do
    keys = proxy [KEYS]
    local n = 0
    for i = 1, #keys do
      if keys [i] == Repository.REFERS then
        n = i
        break
      end
    end
    if n == 0 then
      return proxy
    end
    proxy = nil
    for l = #layers, 1, -1 do
      local layer = layers [l] [KEYS] [1]
      local data  = contents [layer]
      if type (data) ~= "table" then
        break
      end
      for j = 2, n do
        local key = keys [j]
        data = data [key]
        if type (data) ~= "table" then
          data = nil
          break
        end
      end
      if data ~= nil then
        proxy = repository [keys [1]]
        for k = 1, #data do
          proxy = proxy [data [k]]
        end
        for k = n+1, #keys do
          proxy = proxy [keys [k]]
        end
        break
      end
    end
    if proxy == nil then
      return nil
    end
  end
end

function Proxy.__newindex (proxy, key, value)
  if type (key) == "table" then
    error "Not implemented"
  end
  local repository = proxy [REPOSITORY]
  local options    = repository [OPTIONS ]
  local contents   = repository [CONTENTS]
  if key ~= "_" then
    proxy = Proxy.dereference (proxy [key])
  end
  if proxy == nil then
    error "Unknown location"
  end
  value = Repository.import (key, value)
  local data     = contents
  local is_      = (key == "_")
  local keys = proxy [KEYS]
  for i = 1, #keys - 1 do
    key = keys [i]
    if type (data [key]) ~= "table" then
      data [key] = {
        [Repository.VALUE] = data [key],
      }
    end
    data = data [key]
  end
  key = keys [#keys]
  if is_ then
    if type (value) == "table" then
      error "Illegal value"
    elseif type (data [key]) == "table" then
      data [key] [Repository.VALUE] = value
    else
      data [key] = value
    end
  else
    data [key] = value
  end
  -- Clean cache:
  if #keys == 1 or (#keys >= 2 and keys [2] == Repository.DEPENDS) then
 --   repository [LINEARIZED] = {}
    local updated = repository [keys [1]]
    local cache   = repository [LINEARIZED]
    for _, c in pairs (cache) do -- iterate over caches
      local remove = {}
      for k, l in pairs (c) do
        for j = 1, #l do
          if l [j] == updated then
            remove [#remove+1] = k
          end
        end
      end
      for i = 1, #remove do
        c [remove [i]] = nil
      end
    end
  end
  -- Call on_write handler:
  local on_write = options.on_write
  if on_write then
    local filter  = options.filter
    local on_read = options.on_read
    options.filter   = nil
    options.on_read  = nil
    options.on_write = nil
    on_write (proxy, key, value)
    options.filter   = filter
    options.on_read  = on_read
    options.on_write = on_write
  end
end

function Proxy.__pairs (proxy)
  error "Not implemented"
end

function Proxy.__len (proxy)
  error "Not implemented"
end

function Proxy.__tostring (proxy)
  local t    = {}
  local keys = proxy [KEYS]
  for i = 1, #keys do
    t [i] = tostring (keys [i])
  end
  return table.concat (t, ".")
end

function Proxy.__unm (proxy)
  error "Not implemented"
end

function Proxy.__add (lhs, rhs)
  error "Not implemented"
end

function Proxy.__sub (lhs, rhs)
  error "Not implemented"
end

function Proxy.__mul (lhs, rhs)
  error "Not implemented"
end

function Proxy.__div (lhs, rhs)
  error "Not implemented"
end

function Proxy.__mod (lhs, rhs)
  error "Not implemented"
end

function Proxy.__pow (lhs, rhs)
  error "Not implemented"
end

function Proxy.__concat (lhs, rhs)
  error "Not implemented"
end

function Proxy.__eq (lhs, rhs)
  local lrepository = lhs [REPOSITORY]
  local rrepository = rhs [REPOSITORY]
  if lrepository [CONTENTS] ~= rrepository [CONTENTS] then
    return false
  end
  local lkeys = lhs [KEYS]
  local rkeys = rhs [KEYS]
  if #lkeys ~= #rkeys then
    return false
  end
  for i = 1, #lkeys do
    if lkeys [i] ~= rkeys [i] then
      return false
    end
  end
  return true
end

function Proxy.__lt (lhs, rhs)
  error "Not implemented"
end

function Proxy.__le (lhs, rhs)
  error "Not implemented"
end

Repository.nouse = Repository.new ()

Repository.placeholder = Repository.nouse [false]

return Repository