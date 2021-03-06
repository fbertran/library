return function (loader)

  local I18n      = loader.load "cosy.i18n"
  local Webclient = loader.load "cosy.webclient"
  local Dashboard = loader.load "cosy.webclient.dashboard"
  local Profile   = loader.load "cosy.webclient.profile"

  local i18n = I18n.load {
    "cosy.webclient.authentication",
    "cosy.client",
  }
  i18n._locale = Webclient.window.navigator.language

  local Authentication = {
    template = {},
  }
  Authentication.template.headbar = Webclient.template "cosy.webclient.authentication.headbar"
  Authentication.template.sign_up = Webclient.template "cosy.webclient.authentication.sign-up"
  Authentication.template.log_in  = Webclient.template "cosy.webclient.authentication.log-in"

  Authentication.__index = Authentication

  function Authentication.sign_up ()
    local co   = loader.scheduler.running ()
    local info = Webclient.client.server.information ()
    local tos  = Webclient.client.server.tos {
      locale = Webclient.window.navigator.language,
    }
    Webclient.show {
      where    = "main",
      template = Authentication.template.sign_up,
      data     = {
        recaptcha_key = info.captcha,
        tos           = tos.text,
      },
      i18n     = i18n,
    }
    local captcha

    local function check ()
      Webclient.jQuery "#accept":addClass "disabled"
      local result, err = Webclient.client.user.create ({
        identifier = Webclient.jQuery "#identifier":val (),
        password   = Webclient.jQuery "#password-1":val (),
        email      = Webclient.jQuery "#email":val (),
        captcha    = captcha
                 and Webclient.window.grecaptcha:getResponse (captcha),
        tos_digest = Webclient.jQuery "#tos":is ":checked"
                 and tos.digest,
        locale     = Webclient.locale,
      }, {
        try_only = true,
      })
      for _, x in ipairs { "identifier", "email", "password", "captcha", "tos" } do
        Webclient.jQuery ("#" .. x .. "-group"):removeClass "has-error"
        Webclient.jQuery ("#" .. x .. "-group"):addClass    "has-success"
        Webclient.jQuery ("#" .. x .. "-error"):html ("")
      end
      local passwords = {
        Webclient.jQuery "#password-1":val (),
        Webclient.jQuery "#password-2":val (),
      }
      if passwords [1] ~= passwords [2] then
        Webclient.jQuery "#password-group":addClass "has-error"
        local text = i18n ["argument:password:nomatch"] % {}
        Webclient.jQuery "#password-error":html (text)
        result = false
      end
      if result then
        Webclient.jQuery "#accept":removeClass "disabled"
        return true
      elseif err then
        for _, reason in ipairs (err.reasons or {}) do
          if reason.key == "tos_digest" then
            Webclient.jQuery "#tos-group":addClass "has-error"
            local text = i18n ["sign-up:no-tos"] % {}
            Webclient.jQuery "#tos-error":html (text)
          else
            Webclient.jQuery ("#" .. reason.key .. "-group"):addClass "has-error"
            Webclient.jQuery ("#" .. reason.key .. "-error"):html (reason.message)
          end
        end
        return false
      end
    end
    for _, x in ipairs { "identifier", "password-1", "password-2", "email", "tos" } do
      Webclient.jQuery ("#" .. x):focusout (function ()
        Webclient (check)
      end)
    end
    for _, x in ipairs { "captcha", "tos" } do
      Webclient.jQuery ("#" .. x):change (function ()
        Webclient (check)
      end)
    end
    Webclient.jQuery "#accept":click (function ()
      loader.scheduler.wakeup (co)
      return false
    end)

    captcha = Webclient.window.grecaptcha:render ("captcha", Webclient.tojs {
      sitekey  = info.captcha,
      callback = function ()
        Webclient (check)
      end,
      ["expired-callback"] = function ()
        Webclient (check)
      end,
    })

    while true do
      loader.scheduler.sleep (-math.huge)
      if check () then
        Webclient.jQuery "#accept":addClass "disabled"
        Webclient.jQuery "#accept":html [[<i class="fa fa-spinner fa-pulse"></i>]]
        assert (Webclient.client.user.create {
          identifier = Webclient.jQuery "#identifier":val (),
          password   = Webclient.jQuery "#password-1":val (),
          email      = Webclient.jQuery "#email":val (),
          captcha    = captcha
                   and Webclient.window.grecaptcha:getResponse (captcha),
          tos_digest = Webclient.jQuery "#tos":is ":checked"
                   and tos.digest,
          locale     = Webclient.locale,
        })
        Profile ()
        return
      end
    end
  end

  function Authentication.log_in ()
    local co = loader.scheduler.running ()
    Webclient.show {
      where    = "main",
      template = Authentication.template.log_in,
      data     = {},
      i18n     = i18n,
    }
    Webclient.jQuery "#accept":click (function ()
      loader.scheduler.wakeup (co)
      return false
    end)

    while true do
      loader.scheduler.sleep (-math.huge)
      Webclient.jQuery "#accept":addClass "disabled"
      Webclient.jQuery "#accept":html [[<i class="fa fa-spinner fa-pulse"></i>]]
      local result, err = Webclient.client.user.authenticate {
        user     = Webclient.jQuery "#identifier":val (),
        password = Webclient.jQuery "#password"  :val (),
        locale   = Webclient.locale,
      }
      if result then
        Dashboard ()
        return
      else
        Webclient.jQuery "#accept":removeClass "disabled"
        Webclient.jQuery "#accept":html [[<i class="fa fa-check"></i>]]
        Webclient.jQuery "#identifier-group":addClass "has-error"
        Webclient.jQuery "#password-group"  :addClass "has-error"
        Webclient.jQuery "#identifier-error":html (err.message)
      end
    end
  end

  function Authentication.log_out ()
    Webclient.storage:removeItem "cosy:client"
    Webclient.init ()
    Dashboard ()
  end

  local function register_events ()
    Webclient.jQuery "#sign-up":click (function ()
      Webclient (function ()
        Authentication.sign_up ()
        loader.scheduler.wakeup (Authentication.co)
      end)
      return false
    end)
    Webclient.jQuery "#log-in":click (function ()
      Webclient (function ()
        Authentication.log_in ()
        loader.scheduler.wakeup (Authentication.co)
      end)
      return false
    end)
    Webclient.jQuery "#log-out":click (function ()
      Webclient (function ()
        Authentication.log_out ()
        loader.scheduler.wakeup (Authentication.co)
      end)
      return false
    end)
    Webclient.jQuery "#profile":click (function ()
      Profile ()
      return false
    end)
  end

  function Authentication.__call ()
    Webclient (function ()
      Authentication.co = loader.scheduler.running ()
      while true do
        local user = Webclient.client.user.authentified_as {}
        Webclient.show {
          where    = "headbar-user",
          template = Authentication.template.headbar,
          data     = {
            user = user and user.identifier or nil,
          },
          i18n     = i18n,
        }
        register_events ()
        loader.scheduler.sleep (-math.huge)
      end
    end)
  end

  return setmetatable ({}, Authentication)

end
