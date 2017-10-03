return function (loader)

  local Configuration = loader.load "cosy.configuration"
  local Digest        = loader.load "cosy.digest"
  local I18n          = loader.load "cosy.i18n"
  local File          = loader.load "cosy.file"
  local Logger        = loader.load "cosy.logger"
  local Methods       = loader.load "cosy.methods"
  local Nginx         = loader.load "cosy.nginx"
  local Redis         = loader.load "cosy.redis"
  local Store         = loader.load "cosy.store"
  local Token         = loader.load "cosy.token"
  local Value         = loader.load "cosy.value"
  local Posix         = loader.require "posix"
  local Websocket     = loader.require "websocket"
  local Time          = loader.require "socket".gettime

  math.randomseed (Time ())

  Configuration.load {
    "cosy.server",
    "cosy.nginx",
    "cosy.methods",
  }

  loader.logto = Configuration.server.log
  Logger.update ()

  local i18n   = I18n.load {
    "cosy.server",
  }
  i18n._locale = Configuration.locale

  do
    local data = File.decode (Configuration.server.data) or {}
    Configuration.http.port = data.http_port or Configuration.http.port
  end

  local Server = {}

  local function deproxify (t)
    if type (t) ~= "table" then
      return t
    else
      local result = {}
      for k, v in pairs (t) do
        assert (type (k) ~= "table")
        result [k] = deproxify (v)
      end
      return result
    end
  end

  local function call_method (method, parameters, try_only)
    for _ = 1, Configuration.redis.retry or 1 do
      local store = Store.new ()
      local view  = Store.toview (store)
      view = view % Configuration.server.token
      local err
      local ok, result = xpcall (function ()
        local r = method (parameters, view, try_only)
        if not try_only then
          Store.commit (store)
        end
        return r
      end, function (e)
        if tostring (e):match "ERR MULTI" then
          store.__redis:discard ()
        elseif type (e  ) == "table"
           and type (e._) == "table"
           and e._._key   ~= "redis:retry" then
          err = e
        else
          local message = assert (Value.expression (e))
          Logger.debug {
            _      = i18n ["server:exception"],
            reason = message .. " => " .. debug.traceback (),
          }
        end
      end)
      if ok then
        return deproxify (result) or true
      elseif err then
        return nil, err
      end
    end
    return nil, {
      _ = i18n ["error:internal"],
    }
  end

  local function call_parameters (method, parameters)
    parameters.__DESCRIBE = true
    local _, result = pcall (method, parameters)
    return result
  end

  function Server.start ()
    Configuration.server            = {}
    Configuration.server.passphrase = Digest (math.random ())
    Configuration.server.token      = Token.administration ()
    local addserver       = loader.scheduler.addserver

    loader.scheduler.addserver   = function (s, f)
      local ok, port = s:getsockname ()
      if ok then
        Configuration.server.socket = s
        Configuration.server.port   = tonumber (port)
      end
      addserver (s, f)
    end

    Server.ws = Websocket.server.copas.listen {
      interface = Configuration.server.interface,
      port      = Configuration.server.port,
      protocols = {
        cosy = function (ws)
          local message
          local function send (t)
            local response = Value.expression (t)
            Logger.debug {
              _        = i18n ["server:response"],
              request  = message,
              response = response,
            }
            ws:send (response)
          end
          while ws.state == "OPEN" do
            message = ws:receive ()
            Logger.debug {
              _       = i18n ["server:request"],
              request = message,
            }
            if message then
              loader.scheduler.addthread (function ()
                local result, err
                local decoded, request = pcall (Value.decode, message)
                if not decoded or type (request) ~= "table" then
                  return send (i18n {
                    success = false,
                    error   = {
                      _ = i18n ["message:invalid"],
                    },
                  })
                end
                local identifier      = request.identifier
                local operation       = request.operation
                if not request.parameters then
                  request.parameters = {}
                end
                local parameters      = request.parameters
                local try_only        = request.try_only
                local parameters_only = false
                local method          = Methods
                parameters.ip         = ws.ip
                parameters.port       = ws.port
                if operation:sub (-1) == "?" then
                  operation       = operation:sub (1, #operation-1)
                  parameters_only = true
                end
                for name in operation:gmatch "[^:]+" do
                  if method ~= nil then
                    name = name:gsub ("-", "_")
                    method = method [name]
                  end
                end
                if not method then
                  return send (i18n {
                    identifier = identifier,
                    success    = false,
                    error      = {
                      _         = i18n ["server:no-operation"],
                      operation = request.operation,
                    },
                  })
                end
                if parameters_only then
                  result      = call_parameters (method, parameters)
                else
                  result, err = call_method (method, parameters, try_only)
                end
                if type (result) == "function" then
                  send (i18n {
                    identifier = identifier,
                    success    = true,
                    iterator   = true,
                    token      = result (), -- first call returns the token
                  })
                  repeat
                    local subresult, suberr = result ()
                    if subresult then
                      send (i18n {
                        identifier = identifier,
                        success    = true,
                        response   = subresult,
                      })
                    elseif suberr then
                      send (i18n {
                        identifier = identifier,
                        success    = false,
                        finished   = true,
                        error      = suberr,
                      })
                    else
                      send (i18n {
                        identifier = identifier,
                        success    = true,
                        finished   = true,
                      })
                    end
                  until subresult == nil or suberr
                elseif result then
                  send (i18n {
                    identifier = identifier,
                    success    = true,
                    response   = result,
                  })
                else
                  send (i18n {
                    identifier = identifier,
                    success    = false,
                    error      = err,
                  })
                end
                if request.operation == "server:stop" and result then
                  Server.stop ()
                end
              end)
            end
          end
        end
      }
    }
    loader.scheduler.addserver = addserver

    Logger.debug {
      _    = i18n ["websocket:listen"],
      host = Configuration.server.interface,
      port = Configuration.server.port,
    }

    loader.scheduler.addthread (function ()
      loader.scheduler.execute ([[
        rm -rf {{{logs}}}
      ]] % {
        logs = Configuration.filter.log % { pid = "*" },
      })
    end)

    Redis.start ()
    Nginx.start ()

    loader.scheduler.addthread (function ()
      local store = Store.new ()
      local view  = Store.toview (store)
      view = view % Configuration.server.token
      for key in pairs (Configuration.resource ["/"]) do
        if view / key == nil then
          local _ = view + key
        end
      end
      Store.commit (store)
    end)

    do
      File.encode (Configuration.server.data, {
        alias     = loader.alias,
        http      = {
          port      = Configuration.http.port,
          interface = Configuration.http.interface,
        },
        token     = Configuration.server.token,
        interface = Configuration.server.interface,
        port      = Configuration.server.port,
        pid       = Posix.getpid "pid",
      })
      Posix.chmod (Configuration.server.data, "0600")
    end

    loader.scheduler.loop ()
  end

  function Server.stop ()
    os.remove (Configuration.server.data)
    loader.scheduler.removeserver (Configuration.server.socket)
    Nginx.stop ()
    Redis.stop ()
  end

  return Server

end
