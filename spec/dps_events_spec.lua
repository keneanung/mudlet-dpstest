require("spec/spec_helper")

describe("Named GMCP event registration", function()
  local anonCalled

  before_each(function()
    set_time(0)
    anonCalled = false
    -- fail if anonymous registration is attempted
    registerAnonymousEventHandler = function()
      anonCalled = true
      error("anonymous registration should not be used")
    end
    -- provide a named handler to allow registration path
    registerNamedEventHandler = function(handlerName, eventName, fn)
      return handlerName .. ":" .. eventName
    end
    reload_dps({ noSaveStub = true })
    DPS.init()
  end)

  it("does not use anonymous registration", function()
    assert.is_false(anonCalled)
  end)
end)
