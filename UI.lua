-- MoonCat's shared UI, rendered by Cascade (macOS Sequoia).
-- Fluent Add* and WindUI-style calls below share the same Cascade components.
local CASCADE_VERSION = "v1.4.0"
local CASCADE_URL = "https://github.com/cascadeui/Cascade/releases/download/" .. CASCADE_VERSION .. "/dist.luau"
local loaded, cascade = pcall(function()
    local chunk, message = loadstring(game:HttpGet(CASCADE_URL), "Cascade " .. CASCADE_VERSION)
    assert(chunk, message)
    return chunk()
end)
assert(loaded and type(cascade) == "table" and type(cascade.New) == "function",
    "[MoonCat] Unable to load Cascade " .. CASCADE_VERSION .. ": " .. tostring(cascade))

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Library = {
    Version = CASCADE_VERSION,
    IsCascade = true,
    Themes = { "Dark", "Light" },
    Accents = {},
    Theme = "Dark",
    Accent = "Blue",
    Options = {},
    UseAcrylic = true,
    Acrylic = false,
    Transparency = true,
    MinimizeKey = Enum.KeyCode.LeftControl,
    Unloaded = false,
    _connections = {},
}
for name in pairs(cascade.Accents) do
    table.insert(Library.Accents, name)
end
table.sort(Library.Accents)

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Library._connections, connection)
    return connection
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" or Library.Unloaded then return end
    local ok, message = pcall(callback, ...)
    if not ok then warn("[MoonCat UI] " .. tostring(message)) end
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

local function keyCode(value)
    if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then return value end
    if type(value) == "string" then
        local ok, result = pcall(function() return Enum.KeyCode[value] end)
        if ok then return result end
    end
    return nil
end

local icons = {
    home = "house", settings = "gearshape", info = "infoCircle",
    ["door-open"] = "doorLeftHandOpen", ["chevron-right"] = "chevronRight",
    ["banknote-arrow-up"] = "dollarsignCircle", ["triangle-alert"] = "exclamationmarkTriangle",
    ["message-circle-more"] = "bubbleLeft", folders = "folder", monitor = "display",
}
function Library:GetIcon(name)
    if type(name) ~= "string" then return cascade.Symbols.squareStack3dUp end
    if name:match("^rbxassetid://") then return name end
    return cascade.Symbols[icons[name] or name] or cascade.Symbols.squareStack3dUp
end

local function initial(config, fallback)
    if config.Default ~= nil then return config.Default end
    if config.Value ~= nil then return config.Value end
    return fallback
end

local function arguments(id, config)
    if type(id) == "table" then return nil, id end
    return id, config or {}
end

local Control = {}
Control.__index = Control

function Control:_emit()
    safeCall(self.Callback, self.Value)
    for _, callback in ipairs(self._listeners) do safeCall(callback, self.Value) end
end

function Control:SetValue(value)
    if self._destroyed or Library.Unloaded then return self end
    self._revision = (self._revision or 0) + 1
    value = self._normalize(value)
    local changed = not same(self.Value, value)
    self.Value = value
    self._syncing = true
    self.Native.Value = self._toNative(value)
    self._syncing = false
    if self._display then self._display(value) end
    if changed then self:_emit() end
    return self
end

function Control:OnChanged(callback)
    table.insert(self._listeners, callback)
    safeCall(callback, self.Value)
    return self
end

function Control:Lock()
    self.Locked = true
    return self
end

function Control:Unlock()
    self.Locked = false
    return self
end

function Control:SetTitle(value)
    if self._destroyed or Library.Unloaded then return self end
    if self.TitleStack then self.TitleStack.Title = tostring(value) end
    self.Row.SearchIndex = tostring(value)
    return self
end

function Control:SetDesc(value)
    if not self._destroyed and not Library.Unloaded and self.TitleStack then
        self.TitleStack.Subtitle = tostring(value or "")
    end
    return self
end
Control.SetDescription = Control.SetDesc
Control.SetContent = Control.SetDesc

function Control:Destroy()
    self._destroyed = true
    self.Row:Destroy()
end

local function bindControl(control, native, default)
    control.Native = native
    control.Value = control._normalize(default)
    native.Value = control._toNative(control.Value)
    native.ValueChanged = function(_, value)
        if control._syncing or control._destroyed or Library.Unloaded then return end
        control._revision = (control._revision or 0) + 1
        local revision = control._revision
        -- Cascade commits its property after ValueChanged returns. Defer user
        -- callbacks so a callback can revert/normalize a value without that
        -- outer property assignment overwriting the correction.
        task.defer(function()
            if control._destroyed or Library.Unloaded or revision ~= control._revision then return end
            if control.Locked then control:SetValue(control.Value); return end
            control:SetValue(control._fromNative(value))
        end)
    end
    return control
end

local function titleStack(parent, config)
    local stack = parent:TitleStack(config)
    stack.AutomaticSize = Enum.AutomaticSize.Y
    stack.Size = UDim2.new(1, 0, 0, 0)
    for _, label in ipairs({ stack.Structures.Title, stack.Structures.Subtitle }) do
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.Size = UDim2.new(1, 0, 0, 16)
        label.TextWrapped = true
        label.RichText = false
    end
    return stack
end

local Container = {}
Container.__index = Container

function Container:_form()
    if not self.Form then self.Form = self.Native:Form() end
    return self.Form
end

function Container:_control(id, config, title)
    local row = self:_form():Row({ SearchIndex = config.Title or title or "" })
    local stack
    if title ~= false then
        stack = titleStack(row:Left(), {
            Title = config.Title or title or "",
            Subtitle = config.Description or config.Desc or config.Content,
        })
    end
    local control = setmetatable({
        Row = row, TitleStack = stack, Callback = config.Callback,
        _listeners = {}, Locked = config.Locked == true,
        _normalize = function(value) return value end,
        _toNative = function(value) return value end,
        _fromNative = function(value) return value end,
    }, Control)
    if id then Library.Options[id] = control end
    return control
end

function Container:AddSection(config)
    if type(config) == "string" then config = { Title = config } end
    config = config or {}
    local section = self.Native:PageSection({ Title = config.Title, Subtitle = config.Desc or config.Description })
    local container = setmetatable({ Native = section, Window = self.Window }, Container)
    container.Form = section:Form()
    -- WindUI also permits Section() as a heading for following tab controls.
    self.Form = container.Form
    return container
end
Container.Section = Container.AddSection

function Container:AddParagraph(config)
    config = config or {}
    return self:_control(nil, config, "Information")
end
Container.Paragraph = Container.AddParagraph

function Container:AddButton(config)
    local control = self:_control(nil, config, false)
    control.Native = control.Row:Left():Button({
        Label = config.Title or "Continue", State = config.State or "Secondary",
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, UserInputService.TouchEnabled and 34 or 26),
        Pushed = function()
            if not control.Locked and not control._destroyed then safeCall(config.Callback) end
        end,
    })
    control.Native.Structures.Label.AutomaticSize = Enum.AutomaticSize.Y
    control.Native.Structures.Label.Size = UDim2.new(1, 0, 0, 26)
    if config.Desc or config.Description then
        control.TitleStack = titleStack(control.Row:Left(), {
            Title = config.Desc or config.Description,
        })
    end
    function control:SetTitle(value)
        self.Native.Label = tostring(value)
        self.Row.SearchIndex = tostring(value)
        return self
    end
    return control
end
Container.Button = Container.AddButton

function Container:AddToggle(id, config)
    id, config = arguments(id, config)
    local control = self:_control(id, config, "Toggle")
    control._normalize = function(value) return value == true end
    local native = control.Row:Right():Toggle()
    bindControl(control, native, initial(config, false))
    if UserInputService.TouchEnabled then
        local target = Instance.new("TextButton")
        target.Name = "TouchTarget"
        target.BackgroundTransparency = 1
        target.Text = ""
        target.AnchorPoint = Vector2.new(0.5, 0.5)
        target.Position = UDim2.fromScale(0.5, 0.5)
        target.Size = UDim2.fromOffset(44, 44)
        target.ZIndex = 2
        target.Parent = native.Structures.Body.__instance
        connect(target.MouseButton1Click, function()
            if not control.Locked then control:SetValue(not control.Value) end
        end)
        local size = Instance.new("UISizeConstraint")
        size.MinSize = Vector2.new(0, 44)
        size.Parent = control.Row.Structures.Body.__instance
    end
    return control
end
Container.Toggle = Container.AddToggle

function Container:AddDropdown(id, config)
    id, config = arguments(id, config)
    local control = self:_control(id, config, "Select")
    control.Values = table.clone(config.Values or {})
    control.Multi = config.Multi == true
    control._mapValue = id ~= nil -- Fluent returns a set; WindUI returns an array.
    control._normalize = function(value)
        if not control.Multi then
            if type(value) == "number" then value = control.Values[value] end
            return table.find(control.Values, value) and value or nil
        end
        local selected, result = {}, {}
        if type(value) == "table" then
            for key, item in pairs(value) do
                if type(key) == "number" then selected[item] = true
                elseif item == true then selected[key] = true end
            end
        end
        for _, option in ipairs(control.Values) do
            if selected[option] then
                if control._mapValue then result[option] = true else table.insert(result, option) end
            end
        end
        return result
    end
    control._toNative = function(value)
        if not control.Multi then return table.find(control.Values, value) end
        local indices = {}
        for index, option in ipairs(control.Values) do
            if (control._mapValue and value[option]) or (not control._mapValue and table.find(value, option)) then
                table.insert(indices, index)
            end
        end
        return indices
    end
    control._fromNative = function(value)
        if not control.Multi then return control.Values[value] end
        local result = {}
        for _, index in ipairs(type(value) == "table" and value or {}) do
            if control.Values[index] then table.insert(result, control.Values[index]) end
        end
        return result
    end
    local native = control.Row:Right():PopUpButton({
        Options = table.clone(control.Values), Maximum = control.Multi and math.huge or 1,
        AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromOffset(145, 30),
    })
    native.Structures.CurrentTab.AutomaticSize = Enum.AutomaticSize.None
    native.Structures.CurrentTab.Size = UDim2.new(1, -29, 1, 0)
    native.Structures.CurrentTab.TextTruncate = Enum.TextTruncate.AtEnd
    bindControl(control, native, initial(config, nil))
    function control:SetValues(values)
        local previous = self.Value
        self.Values = table.clone(type(values) == "table" and values or {})
        self.Native.Expanded = false
        self.Native.Options = table.clone(self.Values)
        if not self.Multi and previous ~= nil and not table.find(self.Values, previous) then
            previous = self.Values[1]
        end
        return self:SetValue(previous)
    end
    control.Refresh = control.SetValues
    control.Select = control.SetValue
    return control
end
Container.Dropdown = Container.AddDropdown

function Container:AddSlider(id, config)
    id, config = arguments(id, config)
    local range = type(config.Value) == "table" and config.Value or config
    local minimum, maximum = range.Min or 0, range.Max or 100
    local control = self:_control(id, config, "Value")
    local factor = 10 ^ (config.Rounding or 0)
    control._normalize = function(value)
        return math.clamp(math.floor((tonumber(value) or minimum) * factor + 0.5) / factor, minimum, maximum)
    end
    local label = control.Row:Right():Label({ Text = "", LayoutOrder = 2 })
    control._display = function(value) label.Text = tostring(value) .. (config.Suffix or "") end
    bindControl(control, control.Row:Right():Slider({
        Minimum = minimum, Maximum = maximum, Size = UDim2.fromOffset(105, 20),
    }), range.Default or initial(config, minimum))
    control._display(control.Value)
    return control
end
Container.Slider = Container.AddSlider

function Container:AddInput(id, config)
    id, config = arguments(id, config)
    local control = self:_control(id, config, "Text")
    control._normalize = function(value) return tostring(value or "") end
    local native = control.Row:Right():TextField({
        Placeholder = config.Placeholder or "Enter text", Size = UDim2.fromOffset(145, 30),
    })
    native.Structures.Field.AutomaticSize = Enum.AutomaticSize.None
    native.Structures.Field.Size = UDim2.new(1, -12, 1, 0)
    local size = Instance.new("UISizeConstraint")
    size.MinSize = Vector2.new(145, 30)
    size.MaxSize = Vector2.new(145, 30)
    size.Parent = native.Structures.Body.__instance
    return bindControl(control, native, initial(config, ""))
end
Container.Input = Container.AddInput

function Container:AddKeybind(id, config)
    id, config = arguments(id, config)
    local control = self:_control(id, config, "Shortcut")
    control._normalize = function(value) return (keyCode(value) or Library.MinimizeKey).Name end
    control._toNative = keyCode
    control._fromNative = function(value) return value.Name end
    local native = control.Row:Right():KeybindField()
    bindControl(control, native, initial(config, Library.MinimizeKey.Name))
    connect(native.Structures.Field.Focused, function() Library._bindingKey = true end)
    connect(native.Structures.Field.FocusLost, function()
        -- InputEnded is also used by Cascade to finish recording a key.
        task.defer(function() Library._bindingKey = false end)
    end)
    return control
end
Container.Keybind = Container.AddKeybind

function Library:SetTheme(name)
    self.Theme = name == "Light" and "Light" or "Dark"
    if self.App then
        self.App.Theme = cascade.Themes[self.Theme]
        self:ToggleTransparency(self.Transparency)
    end
end

function Library:SetAccent(name)
    self.Accent = cascade.Accents[name] and name or "Blue"
    if self.App then
        self.App.Accent = cascade.Accents[self.Accent]
        self:ToggleTransparency(self.Transparency)
    end
end

function Library:ToggleAcrylic(enabled)
    self.Acrylic = enabled == true
    if self.Window then
        self.Window.Native.UIBlur = self.Acrylic
        self:ToggleTransparency(self.Transparency)
    end
end

function Library:ToggleTransparency(enabled)
    self.Transparency = enabled == true
    if self.App then
        local transparency = self.Transparency and cascade.Themes[self.Theme].Controls.Sidebar[2].Value or 0
        self.App.Theme.Controls.Sidebar[2].Value = transparency
        self.Window.Native.Structures.Body.BackgroundTransparency = transparency
        -- Cascade's theme bindings update on the next scheduler turn. Keep the
        -- transparency setting independent from the optional 3D blur effect.
        task.defer(function()
            if self.Unloaded then return end
            self.Window.Native.Structures.Body.BackgroundTransparency = self.Transparency
                and cascade.Themes[self.Theme].Controls.Sidebar[2].Value or 0
        end)
    end
end

function Library:Notify(config)
    if not self.App or self.Unloaded then return end
    return self.App:Notification({
        App = self.Window.Title, Title = config.Title or "MoonCat",
        Subtitle = (config.Content or config.Desc or "") .. (config.SubContent and ("\n" .. config.SubContent) or ""),
        Icon = config.Icon and self:GetIcon(config.Icon), Duration = config.Duration or 5,
    })
end

function Library:Destroy()
    if self.Unloaded then return end
    self.Unloaded = true
    for _, connection in ipairs(self._connections) do connection:Disconnect() end
    table.clear(self._connections)
    if self.Window then
        self.Window.Native.Draggable = false
        self.Window.Native.Resizable = false
        self.Window.Native.UIBlur = false
    end
    if self.App then self.App:Destroy() end
end

local Window = {}
Window.__index = Window

function Window:_sidebar(visible)
    self._sidebarVisible = visible
    local structures = self.Native.Structures
    structures.SidebarMargins.Size = UDim2.new(0, visible and 200 or 0, 1, 0)
    structures.SidebarMargins:FindFirstChild("UIPadding").PaddingLeft = UDim.new(0, visible and 0 or -200)
    structures.ContentBody.Size = UDim2.new(1, visible and -201 or 0, 1, 0)
    structures.Separator.Visible = visible
    structures.CornerClip.Visible = visible
end

function Window:_tab(parent, config)
    local native = parent:Tab({ Title = config.Title, Icon = Library:GetIcon(config.Icon), Selected = #self.Tabs == 0 })
    local tab = setmetatable({ Native = native, Window = self }, Container)
    table.insert(self.Tabs, tab)
    function tab:Select()
        self.Native.Selected = true
        if self.Window.Compact then self.Window:_sidebar(false) end
    end
    connect(native.MouseButton1Click, function()
        if self.Compact then self:_sidebar(false) end
    end)
    return tab
end

function Window:AddTab(config)
    if not self._section then self._section = self.Native:Section({ Title = "", Disclosure = false }) end
    return self:_tab(self._section, config)
end
Window.Tab = Window.AddTab

function Window:Section(config)
    local native = self.Native:Section({ Title = config.Title, Expanded = config.Opened ~= false, Disclosure = true })
    local window = self
    return { Tab = function(_, tabConfig) return window:_tab(native, tabConfig) end }
end

function Window:SelectTab(index)
    local tab = type(index) == "number" and self.Tabs[index] or index
    if tab then tab:Select() end
end

function Window:SetToggleKey(value)
    Library.MinimizeKey = keyCode(value) or Library.MinimizeKey
    if Library.MinimizeKeybind then Library.MinimizeKeybind:SetValue(Library.MinimizeKey.Name) end
end

function Window:Minimize()
    self.Native.Minimized = not self.Native.Minimized
end
Window.Toggle = Window.Minimize
function Window:ToggleTransparency(value) Library:ToggleTransparency(value) end
function Window:Destroy() Library:Destroy() end

function Window:Tag(config)
    table.insert(self._tags, config.Title)
    self.Native.Subtitle = table.concat(self._tags, " · ")
end

function Window:CreateTopbarButton(name, icon, callback)
    return Library.App:Button({
        Parent = self.Native.Structures.Titlebar.Trailing,
        Label = name:gsub("Button$", ""), State = "Secondary",
        Pushed = function() safeCall(callback) end,
    })
end

function Window:EditOpenButton(config)
    self.OpenButton.Label = config.Title or self.Title
    self.OpenButton.Visible = config.Enabled ~= false and (not config.OnlyMobile or UserInputService.TouchEnabled)
    self._openDraggable = config.Draggable == true
end

function Window:Dialog(config)
    if self._dialog then self._dialog:Close() end
    local overlay = Instance.new("TextButton")
    overlay.Name = "MoonCatDialog"
    overlay.Text = ""
    overlay.AutoButtonColor = false
    overlay.Modal = true
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.4
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.ZIndex = 20
    overlay.Parent = Library.GUI
    local page = Library.App:Page({
        Parent = overlay, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 0.7, 0),
        ZIndex = 21, ClipsDescendants = true,
    })
    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = Vector2.new(440, 300)
    constraint.Parent = page.__container
    local form = page:Form()
    titleStack(form:Row():Left(), { Title = config.Title or "Confirm", Subtitle = config.Content or "" })
    local row = form:Row()
    local window = self
    local dialog = { Closed = false }
    function dialog:Close()
        if self.Closed then return end
        self.Closed = true
        overlay:Destroy()
        window._dialog = nil
    end
    self._dialog = dialog
    for index, button in ipairs(config.Buttons or {}) do
        row:Right():Button({
            Label = button.Title or "Cancel", State = index == 1 and "Primary" or "Secondary",
            Size = UDim2.fromOffset(0, 34),
            Pushed = function()
                if dialog.Closed then return end
                dialog:Close()
                safeCall(button.Callback)
            end,
        })
    end
    return dialog
end

function Library:CreateWindow(config)
    assert(not self.Window, "[MoonCat] This UI instance already has a window")
    local env = type(getgenv) == "function" and getgenv() or _G
    if env.MoonCatUI and env.MoonCatUI ~= self then env.MoonCatUI:Destroy() end
    env.MoonCatUI = self
    self.MinimizeKey = keyCode(config.MinimizeKey) or Enum.KeyCode.LeftControl
    self.Theme = config.Theme == "Light" and "Light" or "Dark"
    self.App = cascade.New({ Theme = cascade.Themes[self.Theme], Accent = cascade.Accents.Blue, WindowPill = false })
    self.GUI = self.App.__instance
    local native = self.App:Window({
        Title = config.Title or "MoonCat Hub", Subtitle = config.SubTitle or config.Author or "by MoonCat",
        Size = config.Size or UDim2.fromOffset(720, 500),
        UIBlur = false, Dropshadow = true, Searching = config.HideSearchBar ~= true,
        Resizable = config.Resizable ~= false, CanZoom = false,
    })
    local window = setmetatable({
        Native = native, Title = config.Title or "MoonCat Hub", Tabs = {}, _tags = {},
        _searching = config.HideSearchBar ~= true, _sidebarVisible = true,
    }, Window)
    self.Window, self.WindowFrame = window, native.Structures.Body

    -- Use the native sidebar icon with our responsive layout, avoiding the
    -- desktop-only 200px toggle animation on portrait screens.
    local sidebarIcon = native.Structures.Titlebar.SidebarButton
    local menuButton = sidebarIcon:Clone()
    menuButton.Name = "MoonCatSidebar"
    menuButton.Parent = sidebarIcon.Parent
    sidebarIcon.Visible = false
    connect(menuButton.MouseButton1Click, function() window:_sidebar(not window._sidebarVisible) end)
    connect(sidebarIcon:GetPropertyChangedSignal("ImageColor3"), function() menuButton.ImageColor3 = sidebarIcon.ImageColor3 end)
    connect(sidebarIcon:GetPropertyChangedSignal("ImageTransparency"), function() menuButton.ImageTransparency = sidebarIcon.ImageTransparency end)

    window.OpenButton = self.App:Button({
        Label = window.Title, Parent = self.GUI, State = "Secondary",
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12),
        Size = UDim2.fromOffset(0, 44), ZIndex = 10,
        Pushed = function() if not window._dragged then window:Minimize() end end,
    })
    local dragStart, dragPosition, dragInput
    connect(window.OpenButton.InputBegan, function(input)
        if not window._openDraggable then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragStart, dragPosition, dragInput = input.Position, window.OpenButton.Position, input
            window._dragged = false
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if not dragStart then return end
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            window._dragged = window._dragged or delta.Magnitude > 6
            window.OpenButton.Position = UDim2.new(dragPosition.X.Scale, dragPosition.X.Offset + delta.X,
                dragPosition.Y.Scale, dragPosition.Y.Offset + delta.Y)
        end
    end)
    connect(UserInputService.InputEnded, function(input, processed)
        if input == dragInput then
            dragStart, dragInput = nil, nil
            task.defer(function() window._dragged = false end)
        end
        if processed or self._bindingKey or UserInputService:GetFocusedTextBox() then return end
        if window._dialog then
            if input.KeyCode == Enum.KeyCode.Escape then window._dialog:Close() end
            return
        end
        local shortcut = self.MinimizeKeybind and keyCode(self.MinimizeKeybind.Value) or self.MinimizeKey
        if input.KeyCode == shortcut then window:Minimize() end
    end)

    local desired = config.Size or UDim2.fromOffset(720, 500)
    local cameraConnection
    local function fit()
        if self.Unloaded or not Workspace.CurrentCamera then return end
        local viewport = Workspace.CurrentCamera.ViewportSize
        if viewport.X <= 0 or viewport.Y <= 0 then return end
        local width = math.min(math.max(desired.X.Offset, 720), math.max(280, viewport.X - 24))
        local height = math.min(math.max(desired.Y.Offset, 350), math.max(220, viewport.Y - 80))
        native.Size = UDim2.fromOffset(width, height)
        native.Position = UDim2.fromScale(0.5, 0.5)
        native.Resizable = config.Resizable ~= false and viewport.X >= 620
        window.OpenButton.Position = UDim2.new(0, 12, 1, -12)
    end
    local function layout()
        local compact = native.Structures.Body.AbsoluteSize.X < 620
        if window.Compact ~= compact then
            window.Compact = compact
            window:_sidebar(not compact)
        end
        native.Searching = window._searching and not compact
    end
    local function watchCamera()
        if cameraConnection then cameraConnection:Disconnect() end
        if Workspace.CurrentCamera then
            cameraConnection = connect(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit)
            fit()
        end
    end
    connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), watchCamera)
    connect(native.Structures.Body:GetPropertyChangedSignal("AbsoluteSize"), layout)
    connect(native.Destroying, function() if not self.Unloaded then self:Destroy() end end)
    watchCamera()
    layout()
    self:ToggleTransparency(config.Transparent ~= false)
    return window
end

return Library
