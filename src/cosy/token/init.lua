if _G.js then
  error "Not available"
end

return function (loader)

  local Configuration = loader.load "cosy.configuration"
  local Digest        = loader.load "cosy.digest"
  local Jwt           = loader.require "jwt"
  local Time          = loader.require "socket".gettime

  math.randomseed (Time ())

  Configuration.load {
    "cosy.nginx",
    "cosy.token",
  }

  if Configuration.token.secret == nil then
    Configuration.token = {
      secret = Digest (math.random ())
    }
  end

  local Token = {}

  function Token.encode (token)
    local options = {
      alg  = Configuration.token.algorithm,
      keys = { private = Configuration.token.secret },
    }
    local result, err = Jwt.encode (token, options)
    if not result then
      error (err)
    end
    return result
  end

  function Token.decode (s)
    local options = {
      alg  = Configuration.token.algorithm,
      keys = { private = Configuration.token.secret },
    }
    local result, err = Jwt.decode (s, options)
    if not result then
      error (err)
    end
    return result
  end

  function Token.administration ()
    local now    = Time ()
    local result = {
      iat      = now,
      nbf      = now - 1,
      exp      = now + Configuration.expiration.administration,
      iss      = Configuration.http.hostname,
      aud      = nil,
      sub      = "cosy:administration",
      jti      = Digest (tostring (now + math.random ())),
      contents = {
        type       = "administration",
        passphrase = Configuration.server.passphrase,
      },
    }
    return Token.encode (result)
  end

  function Token.identification (data)
    local now    = Time ()
    local result = {
      iat      = now,
      nbf      = now - 1,
      exp      = now + Configuration.expiration.identification,
      iss      = Configuration.http.hostname,
      aud      = nil,
      sub      = "cosy:identification",
      jti      = Digest (tostring (now + math.random ())),
      contents = {
        type = "identification",
        data = data,
      },
    }
    return Token.encode (result)
  end

  function Token.validation (data)
    local now    = Time ()
    local result = {
      iat      = now,
      nbf      = now - 1,
      exp      = now + Configuration.expiration.validation,
      iss      = Configuration.http.hostname,
      aud      = nil,
      sub      = "cosy:validation",
      jti      = Digest (tostring (now + math.random ())),
      contents = {
        type       = "validation",
        identifier = data.identifier,
        email      = data.email,
      },
    }
    return Token.encode (result)
  end

  function Token.authentication (data)
    local now    = Time ()
    local result = {
      iat      = now,
      nbf      = now - 1,
      exp      = now + Configuration.expiration.authentication,
      iss      = Configuration.http.hostname,
      aud      = nil,
      sub      = "cosy:authentication",
      jti      = Digest (tostring (now + math.random ())),
      contents = {
        type       = "authentication",
        identifier = data.identifier,
        locale     = data.locale,
      },
    }
    return Token.encode (result)
  end

  return Token

end
