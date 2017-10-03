return function (loader)

  local Configuration = loader.load "cosy.configuration"
  local I18n          = loader.load "cosy.i18n"
  local Default       = loader.load "cosy.configuration.layers".default
  local Layer         = loader.require "layeredata"
  local this          = Layer.reference (Default)

  Configuration.load "cosy.methods"

  local i18n   = I18n.load "cosy.parameters"
  i18n._locale = Configuration.locale

  do
    Default.data = {
      checks = {}
    }
  end

  do
    Default.data.boolean = {
      [Layer.key.refines] = {
        this.data,
      }
    }
    local checks = Default.data.boolean.checks
    checks [1] = function (t)
      local value = t.request [t.key]
      return  type (value) == "boolean"
          or  nil, {
                _ = i18n ["check:is-boolean"],
              }
    end
  end

  do
    Default.data.is_private = {
      [Layer.key.refines] = {
        this.data.boolean,
      }
    }
  end

  do
    Default.data.position = {
      [Layer.key.refines] = {
        this.data,
      },
    }
    local checks = Default.data.position.checks
    checks [1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  type (value) == "table"
          or  nil, {
                _   = i18n ["check:is-table"],
              }
    end
    checks [2] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value.latitude
         and  value.longitude
          or  nil, {
                _   = i18n ["check:is-position"],
              }
    end
  end

  -- String
  -- ------

  do
    Default.data.string = {
      [Layer.key.refines] = {
        this.data,
      },
      min_size = 0,
      max_size = math.huge,
    }
    local checks = Default.data.string.checks
    checks [1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  type (value) == "string"
          or  nil, {
                _   = i18n ["check:is-string"],
              }
    end
    checks [2] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      local size    = t.parameter.min_size
      return  #value >= size
          or  nil, {
                _     = i18n ["check:min-size"],
                count = size,
              }
    end
    checks [3] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      local size    = t.parameter.max_size
      return  #value <= size
          or  nil, {
                _     = i18n ["check:max-size"],
                count = size,
              }
    end
  end

  -- Avatar
  -- ------

  do
    Default.data.avatar = {
      [Layer.key.refines] = {
        this.data.string,
      },
      normal = {
        width  = 400,
        height = 400,
      },
      icon = {
        width  = 32,
        height = 32,
      },
      ascii = {
        width  = 64,
        height = 16,
      },
    }
    local checks = Default.data.avatar.checks
    checks [#checks+1] = function (t)
      local Mime       = loader.require "mime"
      local request    = t.request
      local key        = t.key
      local value      = Mime.unb64 (request [key])
      local filename   = os.tmpname ()
      local file       = io.open (filename, "wb")
      file:write (value)
      file:close ()
      request [key] = {}
      do
        loader.scheduler.execute ([[
          convert "{{{filename}}}" -resize {{{width}}}x{{{height}}} png:"{{{filename}}}-full"
        ]] % {
          filename = filename,
          height   = Configuration.data.avatar.normal.height,
          width    = Configuration.data.avatar.normal.width,
        })
        file = io.open (filename .. "-full", "rb")
        request [key].normal = Mime.b64 (file:read "*all")
        file:close ()
        os.remove (filename .. "-full")
      end
      do
        loader.scheduler.execute ([[
          convert "{{{filename}}}" -resize {{{width}}}x{{{height}}} png:"{{{filename}}}-icon"
        ]] % {
          filename = filename,
          height   = Configuration.data.avatar.icon.height,
          width    = Configuration.data.avatar.icon.width,
        })
        file = io.open (filename .. "-icon", "rb")
        request [key].icon = Mime.b64 (file:read "*all")
        file:close ()
        os.remove (filename .. "-icon")
      end
      do
        loader.scheduler.execute ([[
          convert "{{{filename}}}" bmp3:"{{{filename}}}.bmp"
          img2txt --width="{{{width}}}" --height="{{{height}}}" --format=ansi "{{{filename}}}.bmp" > "{{{filename}}}-ascii"
          rm -f "{{{filename}}}.bmp"
        ]] % {
          filename = filename,
          height   = Configuration.data.avatar.ascii.height,
          width    = Configuration.data.avatar.ascii.width,
        })
        file = io.open (filename .. "-ascii", "rb")
        request [key].ascii = Mime.b64 (file:read "*all")
        file:close ()
        os.remove (filename .. "-ascii")
      end
      os.remove (filename)
      return true
    end
  end

  do
    Default.data.string.trimmed = {
      [Layer.key.refines] = {
        this.data.string,
      }
    }
    local checks = Default.data.string.trimmed.checks
    table.insert (checks, 2, function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      request [key] = value:trim ()
      return true
    end)
  end

  do
    Default.data.ip = {
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
    local checks = Default.data.ip.checks
    -- http://stackoverflow.com/questions/10975935
    local function check_ip (ip)
      do
        local chunks = { ip:match "(%d+)%.(%d+)%.(%d+)%.(%d+)" }
        if #chunks == 4 then
          for _, v in pairs (chunks) do
            if tonumber(v) > 255 then
              return false
            end
          end
          return true
        end
      end
      do
        local chunks = { ip:match (("([a-fA-F0-9]*):"):rep (8):gsub (":$","$")) }
        if #chunks == 8 then
          for _, v in pairs (chunks) do
            if #v > 0 and tonumber (v, 16) > 65535 then
              return false
            end
          end
          return true
        end
      end
    end
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  check_ip (value)
          or  nil, {
                _  = i18n ["check:ip:pattern"],
                ip = value,
              }
    end
  end

  do
    Default.data.captcha = {
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
  end

  do
    Default.data.locale = {
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
    local checks = Default.data.locale.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value:find "^%a%a$"
          or  value:find "^%a%a%-%a%a$"
          or  value:find "^%a%a%_%a%a$"
          or  nil, {
                _      = i18n ["check:locale:pattern"],
                locale = value,
              }
    end
  end

  -- Function
  -- --------

  do
    Default.data.iterator = {
      [Layer.key.refines] = {
        this.data.string,
      },
    }
    local checks = Default.data.iterator.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      -- http://lua-users.org/wiki/SandBoxes
      local environment = {
        assert    = assert,
        coroutine = coroutine,
        error     = error,
        ipairs    = ipairs,
        math      = math,
        next      = next,
        pairs     = pairs,
        pcall     = pcall,
        select    = select,
        string    = string,
        table     = table,
        tonumber  = tonumber,
        tostring  = tostring,
        type      = type,
        unpack    = unpack,
        xpcall    = xpcall,
      }
      -- FIXME: insecure, we should not load bytecode functions!
      if load then
        local f, err = load (value, nil, 'bt', environment)
        if not f then
          return nil, {
            _      = i18n ["check:iterator:function"],
            reason = err,
          }
        end
        request [key] = f
      else
        local f, err = load (value)
        if not f then
          return nil, {
            _      = i18n ["check:iterator:function"],
            reason = err,
          }
        end
        _G.setfenv (f, environment) -- Lua 5.1 specific
        request [key] = f
      end
      if value:byte (1) ~= 27 then
        local _, result = pcall (request [key])
        request [key] = result
      end
      return  type (request [key]) == "function"
          or  nil, {
                _      = i18n ["check:iterator:function"],
                reason = request [key],
              }
    end
  end

  -- Email
  -- -----
  do
    Default.data.email = {
      max_size = 128,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
    local checks = Default.data.email.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      local pattern = "^.*@[%w%.%%%+%-]+%.%w%w%w?%w?$"
      return  value:find (pattern)
          or  nil, {
                _     = i18n ["check:email:pattern"],
                email = value,
              }
    end
  end

  -- Resource
  -- ----
  do
    Default.data.resource = {
      min_size = 1,
      max_size = math.huge,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      },
      identifier = {
        min_size = 1,
        max_size = 32,
        [Layer.key.refines] = {
          this.data.string.trimmed,
        }
      }
    }

    local checks = Default.data.resource.identifier.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value:find "^%w[%w%-_]*$"
          or  nil, {
                _   = i18n ["check:alphanumeric"],
                key = key,
              }
    end
  end

  do
    local checks = Default.data.resource.checks
    checks [#checks+1] = function (t)
      local store   = t.store
      local request = t.request
      local key     = t.key
      local value   = request [key]
      local data    = store / "data"
      for v in value:gmatch "[^/]+" do
        if not v:match "^%w[%w%-_]*$" then
          return  nil, {
            _    = i18n ["check:resource:format"],
            name = v,
          }
        end
        data = data / v
        if not data then
          return  nil, {
            _    = i18n ["check:resource:miss"],
            name = value,
          }
        end
      end
      request [key] = data
      return true
    end
  end

  do
    Default.data.user = {
      [Layer.key.refines] = {
        this.data.resource,
      },
      new_identifier = {
        [Layer.key.refines] = { this.data.resource.identifier },
      },
      new_email = {
        [Layer.key.refines] = { this.data.email },
      },
    }
    do
      local checks = Default.data.user.checks
      checks [#checks+1] = function (t)
        local request = t.request
        local key     = t.key
        local value   = request [key]
        return request [key].type == "user"
            or  nil, {
                  _    = i18n ["check:resource:not-user"],
                  name = value,
                }
      end
    end
    do
      local checks = Default.data.user.new_identifier.checks
      checks [#checks+1] = function (t)
        local store = t.store
        local value = t.request [t.key]
        if store / "data" / value then
          return nil, {
                   _          = i18n ["check:user:exist"],
                   identifier = value,
                 }
        else
          return true
        end
      end
    end
    do
      local checks = Default.data.user.new_email.checks
      checks [#checks+1] = function (t)
        local store = t.store
        local value = t.request [t.key]
        if store / "email" / value then
          return nil, {
                   _     = i18n ["check:email:exist"],
                   email = value,
                 }
        else
          return true
        end
      end
    end
  end

  do
    Default.data.user.active = {
      [Layer.key.refines] = {
        this.data.user,
      },
    }
    local checks = Default.data.user.active.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local user    = request [key]
      return  user.status == "active"
          or  nil, {
                _    = i18n ["check:user:not-active"],
                name = user.identifier,
              }
    end
  end

  do
    Default.data.user.suspended = {
      [Layer.key.refines] = {
        this.data.user,
      },
    }
    local checks = Default.data.user.suspended.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local user    = request [key]
      return  user.status == "suspended"
          or  nil, {
                _    = i18n ["check:user:not-suspended"],
                name = user.identifier,
              }
    end
  end

  do
    Default.data.project = {
      [Layer.key.refines] = {
        this.data.resource,
      },
    }
    local checks = Default.data.project.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  request [key].type == "project"
          or  nil, {
                _    = i18n ["check:resource:not-type"],
                name = value,
                type = "project",
              }
    end
  end

  for i = 1, #(Configuration.resource.project ["/"]) do
    local data = Configuration.resource.project ["/"] [i]
    local id   = data.__keys [#data.__keys]

    Default.data [id] = {
      [Layer.key.refines] = {
        this.data.resource,
      },
    }
    local checks = Default.data [id].checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  request [key].type == id
          or  nil, {
                _    = i18n ["check:resource:not-type"],
                name = value,
                type = id,
              }
    end
  end

  -- Password
  -- --------
  do
    Default.data.password = {
      min_size = 1,
      max_size = 128,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
  end

  do
    Default.data.password.checked = {
      [Layer.key.refines] = {
        this.data.password,
      }
    }
  end

  -- Name
  -- ----
  do
    Default.data.name = {
      min_size = 1,
      max_size = 128,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
  end

  -- Organization
  -- ------------
  do
    Default.data.organization = {
      min_size = 1,
      max_size = 128,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
  end

  -- Homepage
  -- ------------
  do
    Default.data.homepage = {
      min_size = 1,
      max_size = 128,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
  end

  -- Description
  -- -----------
  do
    Default.data.description = {
      min_size = 1,
      max_size = 4096,
      [Layer.key.refines] = {
        this.data.string.trimmed,
      }
    }
  end

  -- Terms of Services Digest
  -- ------------------------
  do
    Default.data.tos = {
      [Layer.key.refines] = {
        this.data.string.trimmed,
      },
    }
    Default.data.tos.digest = {
      [Layer.key.refines] = {
        this.data.string.trimmed,
      },
      min_size = 64,
      max_size = 64,
    }
    local checks = Default.data.tos.digest.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      request [key] = value:lower ()
      return  true
    end
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      local pattern = "^%x+$"
      return  value:find (pattern)
          or  nil, {
                _          = i18n ["check:tos_digest:pattern"],
                tos_digest = value,
              }
    end
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      local Methods = loader.load "cosy.methods"
      local tos     = Methods.server.tos { locale = request.locale }
      return  tos.digest == value
          or  nil, {
                _          = i18n ["check:tos_digest:incorrect"],
                tos_digest = value,
              }
    end
  end

  -- Token
  -- -----
  do
    Default.data.token = {
      [Layer.key.refines] = {
        this.data.string.trimmed,
      },
    }
    local checks = Default.data.token.checks
    checks [#checks+1] = function (t)
      local Token      = loader.load "cosy.token"
      local request    = t.request
      local key        = t.key
      local value      = request [key]
      local ok, result = pcall (Token.decode, value)
      if not ok then
        return nil, {
          _ = i18n ["check:token:invalid"],
        }
      end
      request [key] = result.contents
      return  true
    end
  end

  -- Administration token
  -- --------------------
  do
    Default.data.token.administration = {
      [Layer.key.refines] = {
        this.data.token,
      },
    }
    local checks = Default.data.token.administration.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value.type == "administration"
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value.passphrase == Configuration.server.passphrase
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
  end

  -- Identification token
  -- --------------------
  do
    Default.data.token.identification = {
      [Layer.key.refines] = {
        this.data.token,
      },
    }
    local checks = Default.data.token.identification.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      request [key] = value.data
      return  value.type == "identification"
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
  end

  -- Validation token
  -- ----------------
  do
    Default.data.token.validation = {
      [Layer.key.refines] = {
        this.data.token,
      },
    }
    local checks = Default.data.token.validation.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value.type == "validation"
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
    checks [#checks+1] = function (t)
      local store      = t.store
      local request    = t.request
      local key        = t.key
      local identifier = request [key].identifier
      local user       = store / "data" / identifier
      request [key].user = user
      return  nil
         and  user.type == "user"
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
  end

  -- Authentication Token
  -- --------------------
  do
    Default.data.token.authentication = {
      [Layer.key.refines] = {
        this.data.token,
      },
    }
    local checks = Default.data.token.authentication.checks
    checks [#checks+1] = function (t)
      local request = t.request
      local key     = t.key
      local value   = request [key]
      return  value.type == "authentication"
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
    checks [#checks+1] = function (t)
      local store      = t.store
      local request    = t.request
      local key        = t.key
      local identifier = request [key].identifier
      local user       = store / "data" / identifier
      request [key].user = user
      return  user
         and  user.type   == "user"
         and  user.status == "active"
          or  nil, {
                _ = i18n ["check:token:invalid"],
              }
    end
  end

end
