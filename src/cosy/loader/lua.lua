if #setmetatable ({}, { __len = function () return 1 end }) ~= 1
then
  error "Cosy requires Lua >= 5.2 to run."
end

return function (t)

  t = t or {}
  local loader = {}
  for k, v in pairs (t) do
    loader [k] = v
  end
  loader.home    = os.getenv "HOME" .. "/.cosy/" .. (loader.alias or "default")
  local modules  = setmetatable ({}, { __mode = "kv" })
  loader.hotswap = t.hotswap
                or require "hotswap".new {}
  loader.require = loader.hotswap.require
  loader.load    = function (name)
    if modules [name] then
      return modules [name]
    end
    local module   = loader.require (name) (loader) or true
    modules [name] = module
    return module
  end
  loader.logto     = t.logto
  loader.scheduler = t.scheduler
  if not loader.scheduler then
    loader.scheduler = loader.require "copas.ev"
  end
  loader.hotswap.loaded.copas = loader.scheduler
  package.loaded.copas        = loader.scheduler
  loader.coroutine = t.coroutine
                  or loader.scheduler._coroutine
                  or loader.require "coroutine.make" ()
  _G.coroutine     = loader.coroutine
  loader.request   = t.request
                  or loader.require "copas.http".request
  loader.load "cosy.string"
  loader.hotswap.preload ["websocket.bit"         ] = function ()
    return loader.require "cosy.loader.patches.bit"
  end
  loader.hotswap.preload ["websocket.server_copas"] = function ()
    return loader.require "cosy.loader.patches.server_copas"
  end
  loader.hotswap.preload ["websocket.client_sync"] = function ()
    return loader.require "cosy.loader.patches.client_sync"
  end

  local path = package.searchpath ("cosy.loader.lua", package.path)
  local parts = {}
  for part in path:gmatch "[^/]+" do
    parts [#parts+1] = part
  end

  for _ = 1, 3 do
    parts [#parts] = nil
  end
  loader.lua_modules = (path:find "^/" and "/" or "") .. table.concat (parts, "/")

  for _ = 1, 3 do
    parts [#parts] = nil
  end
  loader.prefix = (path:find "^/" and "/" or "") .. table.concat (parts, "/")

  if path:match "^/" then
    local Lfs = loader.require "lfs"
    local src = loader.prefix .. "/lib/luarocks/rocks/cosy/"
    if Lfs.attributes (src, "mode") ~= "directory" then
      src = loader.prefix .. "/lib/luarocks/rocks/cosy-client/"
    end
    for subpath in Lfs.dir (src) do
      if  subpath ~= "." and subpath ~= ".."
      and Lfs.attributes (src .. "/" .. subpath, "mode") == "directory" then
        src = src .. subpath .. "/src"
        break
      end
    end
    loader.source = src
  else
    loader.source = loader.lua_modules
  end

  assert (os.execute ([[ mkdir -p {{{home}}} ]] % {
    home = loader.home,
  }))

  return loader
end
