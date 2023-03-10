--*****************************************************************************
--* File: lua/modules/ui/lobby/lobby_edited.lua
--* Author: Chris Blackwell
--* Summary: Game selection UI
--*
--* Copyright © 2005 Gas Powered Games, Inc. All rights reserved.
--*****************************************************************************
LOG('Launch KyrOs Lobby')
local GameVersion = import('/lua/version.lua').GetVersion
local UIUtil = import('/lua/ui/uiutil.lua')
local MenuCommon = import('/lua/ui/menus/menucommon.lua')
local Prefs = import('/lua/user/prefs.lua')
local MapUtil = import('/lua/ui/maputil.lua')
local Group = import('/lua/maui/group.lua').Group
local RadioButton = import('/lua/ui/controls/radiobutton.lua').RadioButton
local MapPreview = import('/lua/ui/controls/mappreview.lua').MapPreview
local ResourceMapPreview = import('/lua/ui/controls/resmappreview.lua').ResourceMapPreview
local Popup = import('/lua/ui/controls/popups/popup.lua').Popup
local Slider = import('/lua/maui/slider.lua').Slider
local PlayerData = import('/lua/ui/lobby/data/playerdata.lua').PlayerData
local GameInfo = import('/lua/ui/lobby/data/gamedata.lua')
local WatchedValueArray = import('/lua/ui/lobby/data/watchedvalue/watchedvaluearray.lua').WatchedValueArray
local ItemList = import('/lua/maui/itemlist.lua').ItemList
local LayoutHelpers = import('/lua/maui/layouthelpers.lua')
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local Button = import('/lua/maui/button.lua').Button
local ToggleButton = import('/lua/ui/controls/togglebutton.lua').ToggleButton
local Edit = import('/lua/maui/edit.lua').Edit
local LobbyComm = import('/lua/ui/lobby/lobbyComm.lua')
local Tooltip = import('/lua/ui/game/tooltip.lua')
local Mods = import('/lua/mods.lua')
local FactionData = import('/lua/factions.lua')
local Text = import('/lua/maui/text.lua').Text
local TextArea = import('/lua/ui/controls/textarea.lua').TextArea

local Trueskill = import('/lua/ui/lobby/trueskill.lua')
local round = import('/lua/ui/lobby/trueskill.lua').round
local Player = import('/lua/ui/lobby/trueskill.lua').Player
local Rating = import('/lua/ui/lobby/trueskill.lua').Rating
local ModBlacklist = import('/etc/faf/blacklist.lua').Blacklist
local Teams = import('/lua/ui/lobby/trueskill.lua').Teams
local EscapeHandler = import('/lua/ui/dialogs/eschandler.lua')
local CountryTooltips = import('/lua/ui/help/tooltips-country.lua').tooltip
local SetUtils = import('/lua/system/setutils.lua')
local JSON = import('/lua/system/dkson.lua').json
local UnitsAnalyzer = import('/lua/ui/lobby/UnitsAnalyzer.lua')
local Changelog = import('/lua/ui/lobby/changelog.lua')
-- Uveso - aitypes inside aitypes.lua are now also available as a function.
local aitypes = import('/lua/ui/lobby/aitypes.lua').GetAItypes()

local IsSyncReplayServer = false

local AddUnicodeCharToEditText = import('/lua/UTF.lua').AddUnicodeCharToEditText

if HasCommandLineArg("/syncreplay") and HasCommandLineArg("/gpgnet") then
    IsSyncReplayServer = true
end

local globalOpts = import('/lua/ui/lobby/lobbyOptions.lua').globalOpts
local teamOpts = import('/lua/ui/lobby/lobbyOptions.lua').teamOptions
local AIOpts = import('/lua/ui/lobby/lobbyOptions.lua').AIOpts
local gameColors = import('/lua/gameColors.lua').GameColors
local numOpenSlots = LobbyComm.maxPlayerSlots

-- Add lobby options from AI mods
function ImportModAIOptions()
    local simMods = import('/lua/mods.lua').AllMods()
    local OptionData
    for Index, ModData in simMods do
        if exists(ModData.location..'/lua/AI/LobbyOptions/lobbyoptions.lua') then
            OptionData = import(ModData.location..'/lua/AI/LobbyOptions/lobbyoptions.lua').AIOpts
            for s, t in OptionData do
                table.insert(AIOpts, t)
            end
        end
    end
end
ImportModAIOptions()

-- Maps faction identifiers to their names.
local FACTION_NAMES = {[1] = "uef", [2] = "aeon", [3] = "cybran", [4] = "seraphim", [5] = "random" }

local LAST_GAME_PRESET_NAME = "lastGame"
local rehostPlayerOptions = {} -- Player options loaded from preset, used for rehosting

local formattedOptions = {}
local nonDefaultFormattedOptions = {}
local Warning_MAP = false
local LrgMap = false

local HostUtils
local mapPreviewSlotSwapFrom = 0
local mapPreviewSlotSwap = false

local teamIcons = {
    '/lobby/team_icons/team_no_icon.dds',
    '/lobby/team_icons/team_1_icon.dds',
    '/lobby/team_icons/team_2_icon.dds',
    '/lobby/team_icons/team_3_icon.dds',
    '/lobby/team_icons/team_4_icon.dds',
    '/lobby/team_icons/team_5_icon.dds',
    '/lobby/team_icons/team_6_icon.dds',
}

DebugEnabled = Prefs.GetFromCurrentProfile('LobbyDebug') or ''
local HideDefaultOptions = Prefs.GetFromCurrentProfile('LobbyHideDefaultOptions') == 'true'

local connectedTo = {} -- by UID
CurrentConnection = {} -- by Name
ConnectionEstablished = {} -- by Name
ConnectedWithProxy = {} -- by UID

-- The set of available colours for each slot. Each index in this table contains the set of colour
-- values that may appear in its combobox. Keys in the sub-tables are indexes into allColours,
-- values are the colour values.
availableColours = {}

allAvailableFactionsList = {}

local availableMods = {} -- map from peer ID to set of available mods; each set is a map from "mod id"->true
local selectedSimMods = {} -- Similar map for activated sim mods
local selectedUIMods = {} -- Similar map for activated UI mods

local CPU_Benchmarks = {} -- Stores CPU benchmark data

local function parseCommandlineArguments()
    -- Set of all possible command line option keys.
    -- The client sometimes gives us empty-string as some args, which gets interpreted as that key
    -- having as value the name of the next key. This set lets us interpret that case using the
    -- default option.
    local CMDLINE_ARGUMENT_KEYS = {
        ["/init"] = true,
        ["/country"] = true,
        ["/numgames"] = true,
        ["/mean"] = true,
        ["/clan"] = true,
        ["/deviation"] = true,
        ["/joincustom"] = true,
        ["/gpgnet"] = true,
    }

    local function GetCommandLineArgOrDefault(argname, default)
        local arg = GetCommandLineArg(argname, 1)
        if arg and not CMDLINE_ARGUMENT_KEYS[arg[1]] then
            return arg[1]
        end

        return default
    end

    return {
        PrefLanguage = tostring(string.lower(GetCommandLineArgOrDefault("/country", "world"))),
        isRehost = HasCommandLineArg("/rehost"),
        initName = GetCommandLineArgOrDefault("/init", ""),
        numGames = tonumber(GetCommandLineArgOrDefault("/numgames", 0)),
        playerMean = tonumber(GetCommandLineArgOrDefault("/mean", 1500)),
        playerClan = tostring(GetCommandLineArgOrDefault("/clan", "")),
        playerDeviation = tonumber(GetCommandLineArgOrDefault("/deviation", 500)),
    }
end
local argv = parseCommandlineArguments()

local playerRating = math.floor(Trueskill.round2((argv.playerMean - 3 * argv.playerDeviation) / 100.0) * 100)

local teamTooltips = {
    'lob_team_none',
    'lob_team_one',
    'lob_team_two',
    'lob_team_three',
    'lob_team_four',
    'lob_team_five',
    'lob_team_six',
}

local teamNumbers = {
    "<LOC _No>",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
}

local function ParseWhisper(params)
    local delimStart = string.find(params, " ")
    if delimStart then
        local name = string.sub(params, 1, delimStart-1)
        local targID = FindIDForName(name)
        if targID then
            PrivateChat(targID, string.sub(params, delimStart+1))
        else
            AddChatText(LOC("<LOC lobby_0007>Invalid whisper target."))
        end
    end
end

local commands = {
    pm = ParseWhisper,
    private = ParseWhisper,
    w = ParseWhisper,
    whisper = ParseWhisper,
}

local numberOfChatLinesForFontSize = {
    [9] = 18,
    [10] = 16,
    [11] = 15,
    [12] = 14,
    [13] = 13,
    [14] = 13,
    [15] = 12,
    [16] = 11,
    [17] = 11,
    [18] = 10,
}

local Strings = LobbyComm.Strings

local lobbyComm = false
local localPlayerName = ""
local gameName = ""
local hostID = false
local singlePlayer = false
local GUI = false
local localPlayerID = false
local gameInfo = false
local pmDialog = false
local lastKickMessage = Prefs.GetFromCurrentProfile('lastKickMessage') or ""

local defaultMode =(HasCommandLineArg("/windowed") and "windowed") or Prefs.GetFromCurrentProfile('options').primary_adapter
local windowedMode = defaultMode == "windowed" or (HasCommandLineArg("/windowed"))

function SetWindowedLobby(windowed)
    -- Dont change resolution if user already using windowed mode
    if windowed == windowedMode or defaultMode == 'windowed' then
        return
    end

    if windowed then
        ConExecute('SC_PrimaryAdapter windowed')
    else
        ConExecute('SC_PrimaryAdapter ' .. tostring(defaultMode))
    end

    windowedMode = windowed
end

-- Options = {Padding = {T,R,B,L}, Orientation = V/H, DefaultItemMargin = {T,R,B,L}}
StackPanel = Class(Group) {

    Items = false,
    Orientation = false,
    Padding = false,
    DefaultItemMargin = false,

    __init = function(self, Parent, Options)
        Group.__init(self, Parent)

        -- Properties init
        self.Items = {}
        self.Orientation = "V"
        self.Padding = {0,0,0,0}
        self.DefaultItemMargin = {0,0,0,0}
        if Options then for Name, Value in Options do self[Name] = Value end end

        -- The panel hisself doesn't need hit test
        self:DisableHitTest()   

        -- Background
        self.BG = Bitmap(self)
        self.BG.Top:Set(function() return self.Top() end)
        self.BG.Left:Set(function() return self.Left() end)
        self.BG.Bottom:Set(function() return self.Bottom() end)
        self.BG.Right:Set(function() return self.Right() end)
    end,

    AddItem = function(self, Item, Index)
        if not Index then 
            -- If index is ommited, the item is added at the end of the list
            Index = table.getn(self.Items) + 1 
        elseif Index < 1 or Index > table.getn(self.Items) + 1 then
            -- If index is out of the list range, we just return
            return
        end
        if not Item.Margin then Item.Margin = self.DefaultItemMargin end
        table.insert(self.Items, Index, Item)

        Item:SetParent(self)
        Item.Depth:Set(self.Depth()+1)
        if self:IsHidden() then
            Item:Hide()
        else
            Item:Show()
        end

        if self.Orientation == "V" then
           
            Item.Left:Set(function() return self.Left() + self.Padding[4] + Item.Margin[4] end)
            Item.Right:Set(function() return self.Right() - self.Padding[2] - Item.Margin[2] end)
            Item.Width:Set(function() return Item.Right() - Item.Left() end)

            if Index == 1 then
                -- It's the first item, his top is set to parent top
                Item.Top:Set(function() return self.Top() + self.Padding[1] + Item.Margin[1] end)
            else
                -- It's not the first item, his top is set to previous item's bottom
                local PrevItem = self.Items[Index-1]
                Item.Top:Set(function() return PrevItem.Bottom() + PrevItem.Margin[3] + Item.Margin[1] + 1 end)
            end

            if self.Items[Index + 1] then
                -- There is a item after this one, need top update the next item's top
                local NextItem = self.Items[Index + 1]
                NextItem.Top:Set(function() return Item.Bottom() + Item.Margin[3] + NextItem.Margin[1] + 1 end)
            end

        else
            Item.Top:Set(function() return self.Top() + self.Padding[1] + Item.Margin[1] end)
            Item.Bottom:Set(function() return self.Bottom() - self.Padding[3] - Item.Margin[3] end)
            Item.Height:Set(function() return Item.Bottom() - Item.Top() end)

            if Index == 1 then
                -- It's the first item, his left is set to parent left
                Item.Left:Set(function() return self.Left() + self.Padding[4] + Item.Margin[4] end)
            else
                -- It's not the first item, his left is set to previous item's right
                local PrevItem = self.Items[Index-1]
                Item.Left:Set(function() return PrevItem.Right() + PrevItem.Margin[2] + Item.Margin[4] + 1 end)
            end

            if self.Items[Index + 1] then
                -- There is a item after this one, need top update the next item's left
                local NextItem = self.Items[Index + 1]
                NextItem.Left:Set(function() return Item.Right() + Item.Margin[2] + NextItem.Margin[4] + 1 end)
            end

        end
        return Index
    end,

    RemoveAt = function(self, Index)
        local RemovedItem = table.remove(self.Items, Index)
        if RemovedItem then
            RemovedItem:Hide()
            local Item = self.Items[Index]
            if Item then
                -- There is a item after the removed one
                if self.Orientation == "V" then
                    -- Update next item's top
                    if Index == 1 then
                        -- It's the first item, new first item's top is set to parent top
                        Item.Top:Set(function() return self.Top() + self.Padding[1] + Item.Margin[1]  end)
                    else
                        -- It's not the first item, his top is set to previous item's bottom
                        local PrevItem = self.Items[index-1]
                        Item.Top:Set(function() return PrevItem.Bottom() + PrevItem.Margin[3] + Item.Margin[1] + 1  end)
                    end
                else
                    -- Update next item's left
                    if Index == 1 then
                        -- It's the first item, new first item's left is set to parent left
                        Item.Left:Set(function() return self.Left() + self.Padding[4] + Item.Margin[4]  end)
                    else
                        -- It's not the first item, his left is set to previous item's right
                        local PrevItem = self.Items[index-1]
                        Item.Left:Set(function() return PrevItem.Right() + PrevItem.Margin[2] + Item.Margin[4] + 1  end)
                    end
                end
            end
            return RemovedItem
        end
    end,

    RemoveItem = function(self, Item)
        local Index = self.IndexOf(Item)
        if Index > 0 then
            self.RemoveAt(Index)
            return Index
        end
    end,

    Count = function(self) 
        return table.getn(self.Items)
    end,

    IndexOf = function(self, Item)
        for Index, ListItem in self.Items do
            if Item == ListItem then return Index end
        end
        return 0
    end,

    Clear = function(self)
        local Count = table.getn(self.Items)
        for i = 1, Count do 
            local Item = table.remove(self.Items)
            Item:Hide()
        end
    end,

}

ItemsControl = Class(Group) {
    Items = false,                     -- All items in the list
    FirstVisibleItem = false,           -- The first visible item index in the list (= value of the scrollbar)
    VisibleItemCount = false,           -- The number of visible items
    Panel = false,                  -- The panel containing the items
    DeferRefresh = false,           -- Block the refresh of the list when items are added/removed. Set to true when you add many items and call Refresh when done
    Padding = false,            -- A padding between the items and the external border of the control (Top/right/bottom/left)
    ScrollBarsSize = false,       -- The sizes of the scrollbars (Right/Bottom)
    Orientation = false,              -- The stack orientation, vertical or horizontal
    DefaultItemMargin = false,  -- A margin around each single item (Top/right/bottom/left)
    BackColor = false,


    __init = function(self, Parent, Options)
        Group.__init(self, Parent)

        -- Properties init
        self.Items = {}
        self.FirstVisibleItem = 1
        self.VisibleItemCount = 0
        self.DeferRefresh = false
        self.Padding = {3,3,3,3}
        self.ScrollBarsSize = 14
        self.Orientation = "V"
        self.DefaultItemMargin = {0,0,0,0}
        self.BackColor = '00000000'
        if Options then for Name, Value in Options do self[Name] = Value end end

        -- Panel
        self.Panel = StackPanel(self, {Orientation = self.Orientation})
        self.Panel.Top:Set(function() return self.Top() + self.Padding[1] end)
        if self.Orientation == "V" then
            self.Panel.Right:Set(function() return self.Right() - self.Padding[2] - self.ScrollBarsSize end) 
            self.Panel.Bottom:Set(function() return self.Bottom() - self.Padding[3] end)
        else
            self.Panel.Right:Set(function() return self.Right() - self.Padding[2] end) 
            self.Panel.Bottom:Set(function() return self.Bottom() - self.Padding[3] - self.ScrollBarsSize end)
        end
        self.Panel.Left:Set(function() return self.Left() + self.Padding[4] end)

        -- Background
        self.BG = Bitmap(self)
        self.BG:SetSolidColor(self.BackColor)
        self.BG.Top:Set(function() return self.Top() end)
        self.BG.Left:Set(function() return self.Left() end)
        self.BG.Bottom:Set(function() return self.Bottom() end)
        self.BG.Right:Set(function() return self.Right() end) 


        -- Scrollbar
        self.IsScrollable = function(self, axis)
            return true
        end     
        self.GetScrollValues = function(self, axis)
            -- First item, Last item, First visible item, Last visible item
            return 1, table.getn(self.Items), self.FirstVisibleItem, self.FirstVisibleItem + self.VisibleItemCount - 1
        end 
        -- called when the scrollbar wants to set a new visible top line
        self.ScrollSetTop = function(self, axis, top)
            top = math.floor(top)
            -- Test top value
            if top < 1 then top = 1 end
            if top > table.getn(self.Items) - self.Panel:Count() + 1 then top = table.getn(self.Items) - self.Panel:Count() + 1 end
            if top == self.FirstVisibleItem then return end
            -- Set new top and refresh the list
            self.FirstVisibleItem = top
            self:Refresh()
        end         
        self.ScrollLines = function(self, axis, delta)
            self:ScrollSetTop(axis, self.FirstVisibleItem + math.floor(delta))
        end
        self.ScrollPages = function(self, axis, delta)
            self:ScrollSetTop(axis, self.FirstVisibleItem + math.floor(delta) * self.Panel:Count())
        end
        self.HandleEvent = function(self, event)
            if event.Type == 'WheelRotation' then
                if event.WheelRotation > 0 then
                    self:ScrollLines(nil, -1)
                else
                    self:ScrollLines(nil, 1)
                end

            end
        end 
        self.ScrollToBottom = function(self)
            -- Because the items has not all the same size (number of visible items can change), we need to test if we are really on bottom
            while not self:IsScrolledToBottom() do
                self:ScrollSetTop(nil, table.getn(self.Items) - self.Panel:Count() + 1)
            end        
        end
        self.IsScrolledToBottom = function(self)
            local LastVisibleItem = self.FirstVisibleItem + self.Panel:Count() - 1
            return LastVisibleItem >= table.getn(self.Items)
        end
        if self.Orientation == "V" then
            self.Scroll = UIUtil.CreateLobbyVertScrollbar(self, -self.ScrollBarsSize)
        else
            -- Horizontal scrollbar doesn't exist in UIUtil
            --self.Scroll = UIUtil.CreateLobbyVertScrollbar(self, -self.ScrollBarsSize)
        end
        LayoutHelpers.DepthOverParent(self.Scroll, self, 2)


    end,

    AddItem = function(self, Item, Index)
        -- Check Index
        if not Index then 
            -- If index is ommited, the item is added at the end of the list
            Index = table.getn(self.Items) + 1 
        elseif Index < 1 or Index > table.getn(self.Items) + 1 then
            -- If index is out of the list range, we just return
            return
        end
        -- Default margin to item
        if not Item.Margin then Item.Margin = self.DefaultItemMargin end
        -- Add the item to the list
        table.insert(self.Items, Index, Item)
        Item:SetParent(self)
        Item:Hide() 
        -- We refresh the list
        if not self.DeferRefresh then self:Refresh() end
        return Index
    end,

    RemoveAt = function(self, Index)
        if not Index then 
            -- If index is ommited, the last item of the list is removed
            Index = table.getn(self.Items) 
        elseif Index < 1 or Index > table.getn(self.Items) then
            -- If index is out of the list range, we just return
            return
        end
        -- Remove the item from the list
        local Item = table.remove(self.Items, Index)
        Item:Hide() 
        -- We refresh the list
        if not self.DeferRefresh then self:Refresh() end
        return Item
    end,

    IndexOf = function(self, Item)
        for Index, ListItem in self.Items do
            if Item == ListItem then return Index end
        end
        return 0
    end,

    RemoveItem = function(self, Item)
        local Index = self.IndexOf(Item)
        if Index > 0 then
            self:RemoveAt(Index)
            return Index
        end        
    end,

    Clear = function(self)
        self.DeferRefresh = true
        local Count = table.getn(self.Items)
        for i = Count, 1 do 
            self:RemoveAt(i)
        end
        self:Refresh()
    end,

    Count = function(self) 
        return table.getn(self.Items)
    end,

    Refresh = function(self)
        -- A call to Refresh cancels the DeferRefresh
        self.DeferRefresh = false

        -- We hide all current visible items
        self.Panel:Clear()
        self.VisibleItemCount = 0
        
        -- We place and display the items that must be displayed
        -- Iterate from the first visible item to the last item in the list
        Count = table.getn(self.Items)
        for i = self.FirstVisibleItem, Count do 
            local Item = self.Items[i]

            self.Panel:AddItem(Item)

            if Item.Bottom() > self.Panel.Bottom() then
                -- This item's bottom is outside of the display area, this item should not be visible
                self.Panel:RemoveAt() -- Removes the last item when no index is given
                return  -- The refresh is done
            end

            self.VisibleItemCount = self.VisibleItemCount + 1
        end   
             
    end,
}

RichTextBox = Class(ItemsControl) {

    Texts = false,
    DefaultTextOptions = false,
    DefaultLineOptions = false,

    __init = function(self, Parent, Options)
        -- Properties init
        self.Texts = {}
        self.DefaultTextOptions = {ForeColor = "ffffffff", BackColor = "00000000", FontName = "Arial", FontSize = 12, Padding = {0,0,0,0}, Margin = {0,0,0,0}, DropShadow = false}
        self.DefaultLineOptions = {BackColor = "00000000", Padding = {0,0,0,0}, Margin = {0,0,0,0}}

        -- Init base class
        ItemsControl.__init(self, Parent, Options)

        -- AdvanceFunction
        self.TestTextBlock = Text(self)
        self.TestTextBlock:Hide()
        self.CreateAdvanceFunction = function(self, TextOptions)
            local TextBlock = self.TestTextBlock
            TextBlock:SetFont(TextOptions.FontName, TextOptions.FontSize)
            return function(text)
                TextBlock:SetText(text)
                return TextBlock:Width()
            end
        end
    end,

    AppendText = function(self, String, NewLine, TextOptions, LineOptions)

        local TextWrapper = import('/lua/maui/text.lua')
        local DeferRefresh = self.DeferRefresh
        self.DeferRefresh = true -- We defer the refresh while new lines are added. Refresh is callad at the end

        -- Set text options
        if not TextOptions then TextOptions = {} end
        for Name, Value in self.DefaultTextOptions do
            if not TextOptions[Name] then TextOptions[Name] = Value end
        end 

        -- Set line options
        if not LineOptions then LineOptions = {} end
        for Name, Value in self.DefaultLineOptions do
            if not LineOptions[Name] then LineOptions[Name] = Value end
        end 

        -- Save the text entry
        table.insert(self.Texts, {String, NewLine, TextOptions, LineOptions})

        -- Get available space per line
        local LineWidth = self.Panel.Width()
        local GetLineWidth = function(LineNumber)
            if LineNumber == 1 and not NewLine and table.getn(self.Items) > 0 then 
                -- Return the remaining space on the last line
                return LineWidth - self.Items[table.getn(self.Items)].UsedSpace
            end
            return LineWidth
        end

        -- Get the per line wrapped text
        local wrapped = TextWrapper.WrapText(String, GetLineWidth, self:CreateAdvanceFunction(TextOptions))

        -- Create the lines
        for i, line in wrapped do

            -- Create the TextLine
            local TextLine = false
            if i == 1 and not NewLine and table.getn(self.Items) > 0 then
                -- Take the previous line
                TextLine = self.Items[table.getn(self.Items)]
            else
                -- We need a new line {BackColor = "00000000", Padding = {0,0,0,0}, Margin = {0,0,0,0}}
                TextLine = StackPanel(self, {Orientation = "H"})
                TextLine.BG:SetSolidColor(LineOptions.BackColor)
                TextLine.Margin = LineOptions.Margin
                TextLine.Padding = LineOptions.Padding
                -- Set a height or it wont work
                TextLine.Height:Set(1)
                TextLine.UsedSpace = 0
                self:AddItem(TextLine)
            end

            -- Create the TextBlock {ForeColor = "ffffffff", BackColor = "00000000", FontName = "Arial", FontSize = 12, Padding = {0,0,0,0}, Margin = {0,0,0,0}}
            local TextBlock = Text(self)
            TextBlock:SetFont(TextOptions.FontName, TextOptions.FontSize)
            TextBlock:SetColor(TextOptions.ForeColor)
            TextBlock:SetDropShadow(TextOptions.DropShadow)
            TextBlock.Margin = TextOptions.Margin
            TextBlock.Padding = TextOptions.Padding
            TextBlock:SetText(line)

            -- Set the TextLine height
            local Height = TextBlock.Height() + TextOptions.Margin[1] + TextOptions.Margin[3] + LineOptions.Margin[1] + LineOptions.Margin[3] + LineOptions.Padding[1] + LineOptions.Margin[3]
            if Height > TextLine.Height() then
                TextLine.Height:Set(Height)
            end

            -- Add the TextBlock to the TextLine
            TextLine:AddItem(TextBlock)
            TextLine.UsedSpace = TextLine.UsedSpace + TextBlock.Width()

        end

        -- Refresh the list when all lines are added
        if not DeferRefresh then
            self:Refresh()
        end
  
    end,
}

-- KyrO's Lobby
-- DoSlotBehavior and UpdateGame must be modified to be public (remove local)
local KyrosLobby = {
    team1RatingSum = 0,
    team1GamesSum = 0,
    team2RatingSum = 0,
    team2GamesSum = 0,

    -- Sorts a list
    -- Only local calls
    spairs = function(t, order)
        -- collect the keys
        local keys = {}
        for k in pairs(t) do 
            table.insert(keys, k)
        end

        -- if order function given, sort by it by passing the table and keys a, b,
        -- otherwise just sort the keys 
        if order then
            table.sort(keys, function(a,b) return order(t, a, b) end)
        else
            table.sort(keys)
        end

        -- return the iterator function
        local i = 0
        return function()
            i = i + 1
            if keys[i] then
                return keys[i], t[keys[i]]
            end
        end
    end,
    
    -- Return the map name if available
    -- Only local calls
    GetMapName = function()
        if gameInfo.GameOptions.ScenarioFile and (gameInfo.GameOptions.ScenarioFile ~= "") then
            local scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
            if scenarioInfo and scenarioInfo.name and (scenarioInfo.name ~= "") then
                return scenarioInfo.name
            end
        end
        return nil
    end,

    -- Reads the TeamsSorting from the game preference file and sets the combobox
    -- Only local calls
    SetTeamsSorting = function(self)
        local MapName = self.GetMapName()
        if (MapName) then
            MapName = string.gsub(MapName, "[ .,]", "_")    -- Remove spaces, dots and comas
            local Sorting = GetPreference("TeamsSorting." .. MapName)
            if Sorting then
                GUI.TeamsSorting = Sorting
                GUI.TeamsOrdering:SetTitleText(Sorting)
            end
        end
    end,

    -- Return the team for a slot index
    -- Only local calls
    GetTeamFromSlot = function(SlotIndex) 
        local startPositions = GUI.mapView.startPositions

        if not startPositions[SlotIndex] then
            return -1
        elseif gameInfo.GameOptions.AutoTeams == 'lvsr' then
            local midLine = GUI.mapView.Left() + (GUI.mapView.Width() / 2)
            if startPositions[SlotIndex].Left() < midLine then
                return 1
            else
                return 2
            end
        elseif gameInfo.GameOptions.AutoTeams == 'tvsb' then
            local midLine = GUI.mapView.Top() + (GUI.mapView.Height() / 2)
            if startPositions[SlotIndex].Top() < midLine then
                return 1
            else
                return 2
            end
        elseif gameInfo.GameOptions.AutoTeams == 'pvsi' or gameInfo.GameOptions['RandomMap'] ~= 'Off' then
            if math.mod(SlotIndex, 2) ~= 0 then
                return 1
            else
                return 2
            end
        elseif gameInfo.GameOptions.AutoTeams == 'manual' then
            return gameInfo.AutoTeams[SlotIndex]-1 or 0
        else
            return 0
        end
    end,

    -- Calc and displays the total ratings and number of games for each team
    -- Called at the beggining of ShowGameQuality
    UpdateTeamsSums = function(self)
        self.team1RatingSum = 0
        self.team1GamesSum = 0
        self.team2RatingSum = 0
        self.team2GamesSum = 0

        for i = 1, LobbyComm.maxPlayerSlots do
            if not gameInfo.ClosedSlots[i] and gameInfo.PlayerOptions[i] then
                local team = gameInfo.PlayerOptions[i].Team - 1
                if team == 1 then
                    self.team1RatingSum = self.team1RatingSum + gameInfo.PlayerOptions[i].PL
                    self.team1GamesSum = self.team1GamesSum + gameInfo.PlayerOptions[i].NG
                elseif team == 2 then
                    self.team2RatingSum = self.team2RatingSum + gameInfo.PlayerOptions[i].PL
                    self.team2GamesSum = self.team2GamesSum + gameInfo.PlayerOptions[i].NG
                end
            end
        end

        GUI.Team1TotalRatingsLabel:StreamText(self.team1RatingSum, 30)
        GUI.Team1TotalGamesLabel:StreamText(self.team1GamesSum, 30)
        GUI.Team2TotalRatingsLabel:StreamText(self.team2RatingSum, 30)
        GUI.Team2TotalGamesLabel:StreamText(self.team2GamesSum, 30)

    end,

    -- Places all slots depending on AutoTeams and TeamsSorting
    -- Called at the end of UpdateGame
    ArrangeSlots = function(self)
        LOG("KyrosLobby.ArrangeSlots")

        local UsedSpace = 0

        self:SetTeamsSorting()

        -- Show/hide the TeamsOrdering combo
        if gameInfo.GameOptions.AutoTeams == 'lvsr' or gameInfo.GameOptions.AutoTeams == 'tvsb' or gameInfo.GameOptions.AutoTeams == 'pvsi' then
            GUI.TeamsOrdering:Show()
            GUI.TeamsOrderingLabel:Show()
        else
            GUI.TeamsOrdering:Hide()
            GUI.TeamsOrderingLabel:Hide()
        end

        -- Hide the swap buttons
        for i = 1, 8 do
            GUI.SwapLabels[i]:Hide()
        end

        if (GUI.TeamsSorting ~= "Disabled") and (gameInfo.GameOptions.AutoTeams == 'lvsr' or gameInfo.GameOptions.AutoTeams == 'tvsb' or gameInfo.GameOptions.AutoTeams == 'pvsi') then
            -- New display style

            GUI.SlotsTitleGroup:Show()
            GUI.labelGroup:Hide()

            if gameInfo.GameOptions.AutoTeams == 'lvsr' then
                GUI.Team1PosLabel:StreamText("Left", 30)
                GUI.Team2PosLabel:StreamText("Right", 30)
            elseif gameInfo.GameOptions.AutoTeams == 'tvsb' then
                GUI.Team1PosLabel:StreamText("Top", 30)
                GUI.Team2PosLabel:StreamText("Bottom", 30)
            elseif gameInfo.GameOptions.AutoTeams == 'pvsi' then
                GUI.Team1PosLabel:StreamText("Odd", 30)
                GUI.Team2PosLabel:StreamText("Even", 30)
            end

            local team1Slots = {}
            local team2Slots = {}
            local SlotsInTeam1 = 0
            local SlotsInTeam2 = 0

            for i= 1, LobbyComm.maxPlayerSlots do
                local Slot = GUI.slots[i]
                local team = self.GetTeamFromSlot(i)

                -- Slot
                LayoutHelpers.Reset(Slot)
                Slot.Width:Set(GUI.playerPanel.Width() / 2 - 15)
                Slot.Height:Set(33)

                if team == -1 then
                    -- Unused slot
                    LayoutHelpers.AtLeftTopIn(Slot, GUI.playerPanel, -10000, 0) -- Make unused slot invisible offscreen
                else
                    -- "Slot number", "Slot number (inverted)", "Horizontal position", "Horizontal position (inverted)", "Vertical position", "Vertical position (inverted)"
                    local slotValue = i
                    if GUI.TeamsSorting:find("Slot number") then
                        slotValue = i
                    elseif GUI.TeamsSorting:find("Horizontal position") then
                        slotValue = GUI.mapView.startPositions[i].Left()
                    elseif GUI.TeamsSorting:find("Vertical position") then
                        slotValue = GUI.mapView.startPositions[i].Top()
                    end

                    if team == 1 then
                        table.insert(team1Slots, i, slotValue)
                        SlotsInTeam1 = SlotsInTeam1 + 1
                    elseif team == 2 then
                        table.insert(team2Slots, i, slotValue)
                        SlotsInTeam2 = SlotsInTeam2 + 1
                    end
                end

                -- Background
                LayoutHelpers.FillParent(Slot.SlotBackground, Slot)

                -- Slot number
                LayoutHelpers.AtLeftIn(Slot.slotNumber, Slot, 3)
                LayoutHelpers.AtVerticalCenterIn(Slot.slotNumber, Slot)

                -- Flag
                Slot.KinderCountry.Width:Set(19)
                Slot.KinderCountry.Height:Set(17)
                LayoutHelpers.AtLeftIn(Slot.KinderCountry, Slot, 22)
                LayoutHelpers.AtVerticalCenterIn(Slot.KinderCountry, Slot)

                -- Name
                Slot.name.Width:Set(150) 
                LayoutHelpers.AtLeftIn(Slot.name, Slot, 42)
                LayoutHelpers.AtVerticalCenterIn(Slot.name, Slot, 1)

                -- Faction
                Slot.faction.Width:Set(43)
                LayoutHelpers.AtLeftIn(Slot.faction, Slot, 197)
                LayoutHelpers.AtVerticalCenterIn(Slot.faction, Slot, 1)
                
                -- Color
                Slot.color.Width:Set(59)
                LayoutHelpers.AtLeftIn(Slot.color, Slot, 245)
                LayoutHelpers.AtVerticalCenterIn(Slot.color, Slot, 1)

                -- Team
                Slot.team.Width:Set(59)
                LayoutHelpers.AtLeftIn(Slot.team, Slot, 245) -- Move offscreen to hide
                LayoutHelpers.AtVerticalCenterIn(Slot.team, Slot, 1)

                -- Rating
                LayoutHelpers.AtHorizontalCenterIn(Slot.ratingText, Slot, 140)
                LayoutHelpers.AtVerticalCenterIn(Slot.ratingText, Slot, -5)
                
                -- NumGame
                LayoutHelpers.AtHorizontalCenterIn(Slot.numGamesText, Slot, 140)
                LayoutHelpers.AtVerticalCenterIn(Slot.numGamesText, Slot, 8)
                Slot.numGamesText:SetFont("Arial", 9) 

                -- CPU
                Slot.CPUSpeedBar.Width:Set(Slot.name.Width())
                LayoutHelpers.Below(Slot.CPUSpeedBar, Slot.name, 0)

                -- Ping
                Slot.pingStatus.Width:Set(107)
                LayoutHelpers.Below(Slot.pingStatus, Slot.faction, 0)

                -- Ready checkbox
                LayoutHelpers.AtLeftIn(Slot.ready, Slot, 351)
                LayoutHelpers.AtVerticalCenterIn(Slot.ready, Slot, 1)
            end

            -- Sort and place the slots for each team
            -- Team 1
            local index = 0
            for k,v in self.spairs(team1Slots, function(t,a,b) return t[b] > t[a] end) do
                LayoutHelpers.AtLeftTopIn(GUI.slots[k], GUI.playerPanel, 0, index * (GUI.slots[k].Height() + 4) + 60)
                GUI.SwapLabels[index+1].Team1Slot = k
                if lobbyComm:IsHost() then
                    GUI.SwapLabels[index+1]:Show()
                end
                index = index + 1
            end

            -- Team 2
            index = 0
            if GUI.TeamsSorting:find("(inverted)") then
                for k,v in self.spairs(team2Slots, function(t,a,b) return t[b] < t[a] end) do
                    LayoutHelpers.AtRightTopIn(GUI.slots[k], GUI.playerPanel, 0, index * (GUI.slots[k].Height() + 4) + 60)
                    GUI.SwapLabels[index+1].Team2Slot = k
                    if lobbyComm:IsHost() then
                        GUI.SwapLabels[index+1]:Show()
                    end
                    index = index + 1
                end
            else
                for k,v in self.spairs(team2Slots, function(t,a,b) return t[b] > t[a] end) do
                    LayoutHelpers.AtRightTopIn(GUI.slots[k], GUI.playerPanel, 0, index * (GUI.slots[k].Height() + 4) + 60)
                    GUI.SwapLabels[index+1].Team2Slot = k
                    if lobbyComm:IsHost() then
                        GUI.SwapLabels[index+1]:Show()
                    end
                    index = index + 1
                end
            end

            for i = 1, 8 do
                Tooltip.AddControlTooltip(GUI.SwapLabels[i], "Swap " .. GUI.SwapLabels[i].Team1Slot .. " and " .. GUI.SwapLabels[i].Team2Slot)
            end

            -- Calc the used space in playerPanel
            if SlotsInTeam1 > SlotsInTeam2 then
                UsedSpace = SlotsInTeam1 * (33 + 4) + 60
            else
                UsedSpace =  SlotsInTeam2 * (33 + 4) + 60
            end

        else
            -- Old display style
            GUI.SlotsTitleGroup:Hide()
            GUI.labelGroup:Show()

            -- Replace all slots. 
            for i= 1, LobbyComm.maxPlayerSlots do

                local Slot = GUI.slots[i]
                local team = self.GetTeamFromSlot(i)

                -- Slot
                LayoutHelpers.Reset(Slot)
                Slot.Width:Set(GUI.playerPanel.Width())
                Slot.Height:Set(19)

                if team == -1 then
                    LayoutHelpers.AtLeftTopIn(Slot, GUI.playerPanel, -10000, 0) -- Make unused slot invisible
                else
                    LayoutHelpers.AtLeftTopIn(Slot, GUI.playerPanel, 0, i * (Slot.Height() + 3) - 3)
                    UsedSpace = (i + 1) * (Slot.Height() + 3) - 3
                end

                -- Background
                LayoutHelpers.FillParent(Slot.SlotBackground, Slot)

                -- Slot number
                LayoutHelpers.AtLeftIn(Slot.slotNumber, Slot, 3)
                LayoutHelpers.AtVerticalCenterIn(Slot.slotNumber, Slot)

                -- Flag
                Slot.KinderCountry.Width:Set(19)
                Slot.KinderCountry.Height:Set(17)
                LayoutHelpers.AtLeftIn(Slot.KinderCountry, Slot, 23)
                LayoutHelpers.AtVerticalCenterIn(Slot.KinderCountry, Slot)

                -- Rating
                LayoutHelpers.AtLeftIn(Slot.ratingText, Slot, 49)
                LayoutHelpers.AtVerticalCenterIn(Slot.ratingText, Slot)

                -- NumGame
                LayoutHelpers.AtLeftIn(Slot.numGamesText, Slot, 93)
                LayoutHelpers.AtVerticalCenterIn(Slot.numGamesText, Slot)
                Slot.numGamesText:SetFont("Arial", 14) 

                -- Name
                Slot.name.Width:Set(257)
                LayoutHelpers.AtLeftIn(Slot.name, Slot, 135)
                LayoutHelpers.AtVerticalCenterIn(Slot.name, Slot, 1)

                -- Color
                Slot.color.Width:Set(59)
                LayoutHelpers.AtLeftIn(Slot.color, Slot, 397)
                LayoutHelpers.AtVerticalCenterIn(Slot.color, Slot, 1)

                -- Faction
                Slot.faction.Width:Set(59)
                LayoutHelpers.AtLeftIn(Slot.faction, Slot, 467)
                LayoutHelpers.AtVerticalCenterIn(Slot.faction, Slot, 1)

                -- Team
                Slot.team.Width:Set(59)
                LayoutHelpers.AtLeftIn(Slot.team, Slot, 537)
                LayoutHelpers.AtVerticalCenterIn(Slot.team, Slot, 1)

                -- CPU
                Slot.CPUSpeedBar.Width:Set(62)
                LayoutHelpers.AtLeftIn(Slot.CPUSpeedBar, Slot, 607)
                LayoutHelpers.AtVerticalCenterIn(Slot.CPUSpeedBar, Slot, 1)

                -- Ping
                Slot.pingStatus.Width:Set(62)
                LayoutHelpers.AtLeftIn(Slot.pingStatus, Slot, 679)
                LayoutHelpers.AtVerticalCenterIn(Slot.pingStatus, Slot, 1)

                -- Ready checkbox
                LayoutHelpers.AtLeftIn(Slot.ready, Slot, 751)
                LayoutHelpers.AtVerticalCenterIn(Slot.ready, Slot, 1)

                if singlePlayer then
                    Slot.ready:Hide()
                    Slot.CPUSpeedBar:Hide()
                    Slot.pingStatus:Hide()
                end

            end

        end

        -- Resize the playerPanel and the ChatBox
        GUI.playerPanel.Bottom:Set(function() return GUI.playerPanel.Top() + UsedSpace end)
        GUI.chatDisplay:Refresh()   -- Need to refresh because size changed

        LOG("KyrosLobby.ArrangeSlots_End")

    end,

    -- Create all slots controls and the slots headers
    -- Replaces CreateSlotsUI from main code
    CreateSlotsUI = function(self)
        LOG("KyrosLobby.CreateSlotsUI")

        local Combo = import('/lua/ui/controls/combo.lua').Combo
        local BitmapCombo = import('/lua/ui/controls/combo.lua').BitmapCombo
        local StatusBar = import('/lua/maui/statusbar.lua').StatusBar

        -- Need to adapt a few UI controls
        -- Correct PlayerPanel size and position
        LayoutHelpers.AtLeftTopIn(GUI.playerPanel, GUI.panel, 5, 82)
        GUI.playerPanel.Width:Set(790)
        GUI.playerPanel.Height:Set(367)
        -- We dont need the mod label. We set the mod name into the title label
        GUI.titleText:SetText(GUI.ModFeaturedLabel:GetText())
        GUI.ModFeaturedLabel:Hide()
        -- Move the title label
        LayoutHelpers.AtLeftTopIn(GUI.titleText, GUI.panel, 27, 20)
        GUI.titleText:SetFont('Arial Gras', 17)
        -- Hide the logo and the version
        LayoutHelpers.AtLeftTopIn(GUI.logo, GUI, -1000, 1)
        -- Recreate the logo
        GUI.logo = Bitmap(GUI.panel, '/textures/ui/common/scx_menu/lan-game-lobby/logo.dds')
        LayoutHelpers.AtLeftTopIn(GUI.logo, GUI.panel, 1, 18)
        -- Recreate the version
        GUI.gameVersionText = UIUtil.CreateText(GUI.panel, "FAF Lobby " .. GameVersion(), 9, UIUtil.bodyFont)
        GUI.gameVersionText:SetColor('677983')
        LayoutHelpers.AtLeftTopIn(GUI.gameVersionText, GUI.panel, 70, 3)

        -- Title labels for the 2 teams

        local SlotsTitleGroup = Group(GUI.playerPanel)
        SlotsTitleGroup.Width:Set(GUI.playerPanel.Width())
        LayoutHelpers.AtLeftTopIn(SlotsTitleGroup, GUI.playerPanel, 0, 20)
        GUI.SlotsTitleGroup = SlotsTitleGroup

        local Team1TitleLabel = UIUtil.CreateText(SlotsTitleGroup, "Team 1", 16, 'Arial Gras', true)
        LayoutHelpers.AtTopIn(Team1TitleLabel, SlotsTitleGroup)
        LayoutHelpers.AtHorizontalCenterIn(Team1TitleLabel, SlotsTitleGroup, -SlotsTitleGroup.Width() / 4 - 15)
        GUI.Team1TitleLabel = Team1TitleLabel

        local Team1PosLabel = UIUtil.CreateText(SlotsTitleGroup, "Top", 11, 'Arial Gras', true)
        LayoutHelpers.CenteredBelow(Team1PosLabel, Team1TitleLabel)
        GUI.Team1PosLabel = Team1PosLabel

        local Team2TitleLabel = UIUtil.CreateText(SlotsTitleGroup, "Team 2", 16, 'Arial Gras', true)
        LayoutHelpers.AtTopIn(Team2TitleLabel, SlotsTitleGroup)
        LayoutHelpers.AtHorizontalCenterIn(Team2TitleLabel, SlotsTitleGroup, SlotsTitleGroup.Width() / 4 +15)
        GUI.Team2TitleLabel = Team2TitleLabel

        local Team2PosLabel = UIUtil.CreateText(SlotsTitleGroup, "Bottom", 11, 'Arial Gras', true)
        LayoutHelpers.CenteredBelow(Team2PosLabel, Team2TitleLabel)
        GUI.Team2PosLabel = Team2PosLabel

        local TotalRatingsLabel = UIUtil.CreateText(SlotsTitleGroup, " vs ", 16, 'Arial Gras', true)
        LayoutHelpers.AtTopIn(TotalRatingsLabel, SlotsTitleGroup)
        LayoutHelpers.AtHorizontalCenterIn(TotalRatingsLabel, SlotsTitleGroup)
        GUI.TotalRatingsLabel = TotalRatingsLabel

        local Team1TotalRatingsLabel = UIUtil.CreateText(SlotsTitleGroup, "0", 16, 'Arial Gras', true)
        LayoutHelpers.LeftOf(Team1TotalRatingsLabel, TotalRatingsLabel)
        GUI.Team1TotalRatingsLabel = Team1TotalRatingsLabel
        
        local Team1TotalGamesLabel = UIUtil.CreateText(SlotsTitleGroup, "0", 11, 'Arial Gras', true)
        LayoutHelpers.CenteredBelow(Team1TotalGamesLabel, Team1TotalRatingsLabel)
        GUI.Team1TotalGamesLabel = Team1TotalGamesLabel

        local Team2TotalRatingsLabel = UIUtil.CreateText(SlotsTitleGroup, "0", 16, 'Arial Gras', true)
        LayoutHelpers.RightOf(Team2TotalRatingsLabel, TotalRatingsLabel)
        GUI.Team2TotalRatingsLabel = Team2TotalRatingsLabel

        local Team2TotalGamesLabel = UIUtil.CreateText(SlotsTitleGroup, "0", 11, 'Arial Gras', true)
        LayoutHelpers.CenteredBelow(Team2TotalGamesLabel, Team2TotalRatingsLabel)
        GUI.Team2TotalGamesLabel = Team2TotalGamesLabel

        -- Teams sorting Combo

        local TeamsOrderingLabel = UIUtil.CreateText(GUI.playerPanel, "Teams sorting :", 11, 'Arial', true)
        LayoutHelpers.AtLeftIn(TeamsOrderingLabel, GUI.playerPanel, 0)
        LayoutHelpers.AtTopIn(TeamsOrderingLabel, GUI.playerPanel, -18)
        GUI.TeamsOrderingLabel = TeamsOrderingLabel

        local TeamsOrderingCombo = Combo(GUI.playerPanel, 11, 12, true, nil, "UI_Tab_Rollover_01", "UI_Tab_Click_01")
        TeamsOrderingCombo.Width:Set(160)
        LayoutHelpers.RightOf(TeamsOrderingCombo, TeamsOrderingLabel, 10)
        TeamsOrderingCombo:AddItems({"Disabled", "Slot number", "Slot number (inverted)", "Horizontal position", "Horizontal position (inverted)", "Vertical position", "Vertical position (inverted)"})
        Tooltip.AddComboTooltip(TeamsOrderingCombo, "Choose how the 2 teams are sorted")
        GUI.TeamsOrdering = TeamsOrderingCombo
        GUI.TeamsSorting = "Slots"
        TeamsOrderingCombo:SetTitleText("Slots")

        local KyrosLobbyVar = self
        TeamsOrderingCombo.OnClick = function(self, index, text)
            GUI.TeamsOrdering:SetTitleText(text)
            GUI.TeamsSorting = text
            local MapName = string.gsub(KyrosLobbyVar.GetMapName(), "[ .,]", "_")
            if MapName and MapName ~= "" then
                SetPreference("TeamsSorting." .. MapName, text)
            end
            KyrosLobbyVar:ArrangeSlots()
        end

        -- Swap buttons between the 2 teams

        GUI.SwapLabels = {}
        for i = 1, 8 do
            local SwapLabel = TextArea(GUI.playerPanel, 16, 13)
            local swapBackground = Bitmap(SwapLabel, UIUtil.SkinnableFile("/SLOT/slot-player_other.dds"))
            GUI.SwapLabels[i] = SwapLabel
            SwapLabel:SetFont('Arial Gras', 10)
            SwapLabel:SetColors("B9BFB9", "00000000", "B9BFB9", "00000000")
            LayoutHelpers.AtLeftTopIn(SwapLabel, GUI.playerPanel, GUI.playerPanel.Width() / 2 - 7, i * 37 + 33)
            SwapLabel:SetText("< >")
            Tooltip.AddControlTooltip(SwapLabel, 'Swap')

            swapBackground.Top:Set(function() return math.floor(SwapLabel.Top() - 3) end)
            swapBackground.Left:Set(function() return math.floor(SwapLabel.Left() - 4) end)
            swapBackground.Bottom:Set(function() return math.floor(SwapLabel.Bottom() + 3) end)
            swapBackground.Right:Set(function() return math.floor(SwapLabel.Right() + 2) end)
            SwapLabel.index = i   
            SwapLabel.Team1Slot = 0
            SwapLabel.Team2Slot = 0     
            SwapLabel.OnClick = function(self)
                local player1 = gameInfo.PlayerOptions[self.Team1Slot]
                if not player1 then
                    HostUtils.SwapPlayers(self.Team2Slot, self.Team1Slot)
                else
                    HostUtils.SwapPlayers(self.Team1Slot, self.Team2Slot)
                end
            end
        end

        -- Old style slots header


        local labelGroup = Group(GUI.playerPanel)
        labelGroup.Width:Set(GUI.playerPanel.Width())
        labelGroup.Height:Set(19)
        LayoutHelpers.AtLeftTopIn(labelGroup, GUI.playerPanel, 0, 0)
        GUI.labelGroup = labelGroup

        --local COLUMN_POSITIONS = {1,  21, 47, 91, 133, 395, 465, 535, 605, 677, 749}
        --local COLUMN_WIDTHS =    {20, 20, 45, 45, 257, 59, 59, 59, 62, 62, 51}

        local label = UIUtil.CreateText(labelGroup, "#", 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 3, 0)

        local label = UIUtil.CreateText(labelGroup, "R", 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 49, 0)

        local label = UIUtil.CreateText(labelGroup, "G", 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 93, 0)

        local label = UIUtil.CreateText(labelGroup, LOC("<LOC NICKNAME>Nickname"), 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 135, 0)

        local label = UIUtil.CreateText(labelGroup, "<LOC lobui_0214>Color", 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 397, 0)

        local label = UIUtil.CreateText(labelGroup, "<LOC lobui_0215>Faction", 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 467, 0)

        local label = UIUtil.CreateText(labelGroup, "<LOC lobui_0216>Team", 14, 'Arial Gras', true)
        LayoutHelpers.AtLeftTopIn(label, labelGroup, 537, 0)

        if not singlePlayer then
            local label = UIUtil.CreateText(labelGroup, "<LOC lobui_0450>CPU", 14, 'Arial Gras', true)
            LayoutHelpers.AtLeftTopIn(label, labelGroup, 607, 0)

            local label = UIUtil.CreateText(labelGroup, "<LOC lobui_0451>Ping", 14, 'Arial Gras', true)
            LayoutHelpers.AtLeftTopIn(label, labelGroup, 679, 0)

            local label = UIUtil.CreateText(labelGroup, "<LOC lobui_0218>Ready", 14, 'Arial Gras', true)
            LayoutHelpers.AtLeftTopIn(label, labelGroup, 753, 0)
        end

        -- Slots

        for i= 1, LobbyComm.maxPlayerSlots do
            -- Capture the index in the current closure so it's accessible on callbacks
            local curRow = i

            -- Slot
            local newSlot = Group(GUI.playerPanel)
            GUI.slots[i] = newSlot

            -- Default mouse behaviours for the slot.
            local defaultHandler = function(self, event)
                if curRow > numOpenSlots then
                    return
                end

                local associatedMarker = GUI.mapView.startPositions[curRow]
                if event.Type == 'MouseEnter' then
                    if gameInfo.GameOptions['TeamSpawn'] == 'fixed' then
                        associatedMarker.indicator:Play()
                    end
                elseif event.Type == 'MouseExit' then
                    associatedMarker.indicator:Stop()
                elseif event.Type == 'ButtonDClick' then
                    DoSlotBehavior(curRow, 'occupy', '')
                end
                return Group.HandleEvent(self, event)
            end
            newSlot.HandleEvent = defaultHandler

            -- Background
            local slotBackground = Bitmap(GUI, UIUtil.SkinnableFile("/SLOT/slot-dis.dds"))
            newSlot.SlotBackground = slotBackground

            -- Slot number
            local slotNumber = UIUtil.CreateText(newSlot, i, 14, 'Arial', true)
            newSlot.slotNumber = slotNumber
            newSlot.tooltipnumber = Tooltip.AddControlTooltip(slotNumber, 'slot_number')

            -- Flag
            local flag = Bitmap(newSlot, UIUtil.SkinnableFile("/countries/world.dds"))
            newSlot.KinderCountry = flag

            -- Rating
            local ratingText = UIUtil.CreateText(newSlot, "", 14, 'Arial', true)
            ratingText:SetColor('B9BFB9')
            newSlot.ratingText = ratingText

 
            -- NumGame
            local numGamesText = UIUtil.CreateText(newSlot, "", 14, 'Arial', true)
            numGamesText:SetColor('B9BFB9')
            newSlot.numGamesText = numGamesText
            Tooltip.AddControlTooltip(numGamesText, 'num_games')

            -- Name
            local nameLabel = Combo(newSlot, 12, 12, true, nil, "UI_Tab_Rollover_01", "UI_Tab_Click_01")
            nameLabel._text:SetFont('Arial Gras', 14)
            newSlot.name = nameLabel
            
            nameLabel.OnEvent = defaultHandler -- left deal with name clicks
            nameLabel.OnClick = function(self, index, text)
                DoSlotBehavior(curRow, self.slotKeys[index], text)
            end

            nameLabel.OnHide = function() -- Hide the marker when the dropdown is hidden
                local associatedMarker = GUI.mapView.startPositions[curRow]
                if associatedMarker then
                    associatedMarker.indicator:Stop()
                end
            end

            -- Team
            local teamSelector = BitmapCombo(newSlot, teamIcons, 1, false, nil, "UI_Tab_Rollover_01", "UI_Tab_Click_01")
            newSlot.team = teamSelector

            teamSelector.OnClick = function(self, index, text)
                Tooltip.DestroyMouseoverDisplay()
                SetPlayerOption(curRow, 'Team', index)
            end
            Tooltip.AddControlTooltip(teamSelector, 'lob_team')
            Tooltip.AddComboTooltip(teamSelector, teamTooltips)
            teamSelector.OnEvent = defaultHandler

            -- Color
            local colorSelector = BitmapCombo(newSlot, gameColors.PlayerColors, 1, true, nil, "UI_Tab_Rollover_01", "UI_Tab_Click_01")
            newSlot.color = colorSelector

            colorSelector.OnClick = function(self, index)
                if not lobbyComm:IsHost() then
                    lobbyComm:SendData(hostID, { Type = 'RequestColor', Color = index, Slot = curRow })
                    SetPlayerColor(gameInfo.PlayerOptions[curRow], index)
                    UpdateGame()
                else
                    if IsColorFree(index) then
                        lobbyComm:BroadcastData({ Type = 'SetColor', Color = index, Slot = curRow })
                        SetPlayerColor(gameInfo.PlayerOptions[curRow], index)
                        UpdateGame()
                    else
                        self:SetItem(gameInfo.PlayerOptions[curRow].PlayerColor)
                    end
                end
            end
            colorSelector.OnEvent = defaultHandler
            Tooltip.AddControlTooltip(colorSelector, 'lob_color')

            -- Faction (builds the faction tables, and then adds random faction icon to the end)
            local factionBmps = {}
            local factionTooltips = {}
            local factionList = {}
            for index, tbl in FactionData.Factions do
                factionBmps[index] = tbl.SmallIcon
                factionTooltips[index] = tbl.TooltipID
                factionList[index] = tbl.Key
            end
            --table.insert(factionBmps, "/FACTIONSELECTOR/uef/d_up.dds")
            --table.insert(factionBmps, "/FACTIONSELECTOR/aeon/d_up.dds")
            --table.insert(factionBmps, "/FACTIONSELECTOR/cybran/d_up.dds")
            --table.insert(factionBmps, "/FACTIONSELECTOR/seraphim/d_up.dds")
            --table.insert(factionBmps, "/FACTIONSELECTOR/random/d_up.dds")
            table.insert(factionBmps, "/faction_icon-sm/random_ico.dds")
            table.insert(factionTooltips, 'lob_random')
            table.insert(factionList, 'random')
            allAvailableFactionsList = factionList

            local factionSelector = BitmapCombo(newSlot, factionBmps, table.getn(factionBmps), nil, nil, "UI_Tab_Rollover_01", "UI_Tab_Click_01")
            newSlot.faction = factionSelector
            newSlot.AvailableFactions = factionList

            factionSelector.OnClick = function(self, index)
                SetPlayerOption(curRow, 'Faction', index)
                if curRow == FindSlotForID(FindIDForName(localPlayerName)) then
                    local fact = GUI.slots[FindSlotForID(localPlayerID)].AvailableFactions[index]
                    for ind,value in allAvailableFactionsList do
                        if fact == value then
                            GUI.factionSelector:SetSelected(ind)
                            break
                        end
                    end
                end

                Tooltip.DestroyMouseoverDisplay()
            end
            Tooltip.AddControlTooltip(factionSelector, 'lob_faction')
            Tooltip.AddComboTooltip(factionSelector, factionTooltips)
            factionSelector.OnEvent = defaultHandler
    
            -- CPU
            local barMax = 450
            local barMin = 0
            local CPUSpeedBar = StatusBar(newSlot, barMin, barMax, false, false,
                UIUtil.UIFile('/game/unit_bmp/bar_black_bmp.dds'),
                UIUtil.UIFile('/game/unit_bmp/bar_purple_bmp.dds'),
                true)
            newSlot.CPUSpeedBar = CPUSpeedBar
            CPU_AddControlTooltip(CPUSpeedBar, 0, curRow)
            CPUSpeedBar.CPUActualValue = 450
            CPUSpeedBar.barMax = barMax

            -- Ping
            barMax = 1000
            barMin = 0
            local pingStatus = StatusBar(newSlot, barMin, barMax, false, false,
                UIUtil.SkinnableFile('/game/unit_bmp/bar-back_bmp.dds'),
                UIUtil.SkinnableFile('/game/unit_bmp/bar-01_bmp.dds'),
                true)
            newSlot.pingStatus = pingStatus
            Ping_AddControlTooltip(pingStatus, 0, curRow)

            -- Ready Checkbox
            local readyBox = UIUtil.CreateCheckbox(newSlot, '/CHECKBOX/')
            newSlot.ready = readyBox

            readyBox.OnCheck = function(self, checked)
                UIUtil.setEnabled(GUI.becomeObserver, not checked)
                if checked then
                    DisableSlot(curRow, true)
                else
                    EnableSlot(curRow)
                end
                SetPlayerOption(curRow, 'Ready', checked)
            end

            -- Helpers
            newSlot.HideControls = function()
                -- hide these to clear slot of visible data
                flag:Hide()
                ratingText:Hide()
                numGamesText:Hide()
                factionSelector:Hide()
                colorSelector:Hide()
                teamSelector:Hide()
                CPUSpeedBar:Hide()
                pingStatus:Hide()
                readyBox:Hide()
            end
            newSlot.HideControls()

            if singlePlayer then
                -- TODO: Use of groups may allow this to be simplified...
                readyBox:Hide()
                CPUSpeedBar:Hide()
                pingStatus:Hide()
            end

        end

        self:ArrangeSlots()
        LOG("KyrosLobby.CreateSlotsUI_End")
    end,

    -- Return the prefered slot number
    -- Place KyrosLobby:MoveToPreferedSlot(1) at the end of lobbyComm.Hosting
    -- and KyrosLobby:MoveToPreferedSlot(data.Slot) at the end of lobbyComm.DataReceived > elseif data.Type == 'SlotAssigned' then
    MoveToPreferedSlot = function(self, FromSlot)
        local MapName = string.gsub(self.GetMapName(), "[ .,]", "_")
        local PreferedSlots = Prefs.GetFromCurrentProfile("PreferedSlots") or {}
        if PreferedSlots[MapName] then
            local PreferedSlot = PreferedSlots[MapName]
            if lobbyComm:IsHost() then
                if GUI.mapView.startPositions[PreferedSlot] then
                    HostUtils.MovePlayerToEmptySlot(FromSlot, PreferedSlot)
                end
            else
                lobbyComm:SendData(hostID, {Type = 'MovePlayer', CurrentSlot = FromSlot, RequestedSlot = PreferedSlot})
            end
        end
    end,

    -- Execute chat commands
    -- Place if not KyrosLobby.Commands:Handle(text) then PublicChat(text) end in GUI.chatEdit.OnEnterPressed
    Commands = {
        PlayerFilters = {},
        KyrosLobby = {},

        Handle = function(self, text)
            if string.sub(text, 1, 1) == '/' then
                local spaceStart = string.find(text, " ") or string.len(text) + 1
                local comKey = string.sub(text, 2, spaceStart - 1)
                local params = string.sub(text, spaceStart + 1)
                local commands = {
                    pm = self.pm,
                    private = self.pm,
                    w = self.pm,
                    whisper = self.pm,
                    ban = self.ban,
                    unban = self.unban,
                    cpuscores = self.cpuscores,
                    cpuscore = self.cpuscore,
                    cpulimit = self.cpulimit,
                    ranklimit = self.ranklimit,
                    gameslimit = self.gameslimit,
                    myslot = self.myslot,
                    info = self.info,
                    reminfo = self.reminfo,
                    stats = self.stats,
                    help = self.help,
                }
                local commandFunc = commands[string.lower(comKey)]
                if not commandFunc then
                    AddChatText(LOCF("<LOC lobui_0396>Command Not Known: %s", comKey))
                else
                    commandFunc(self, params)
                end
                return text
            else
                return nil
            end
        end,

        pm = function(self, params)
            local delimStart = string.find(params, " ")
            if delimStart then
                local name = string.sub(params, 1, delimStart-1)
                local targID = false
                for k, player in gameInfo.PlayerOptions:pairs() do
                    if string.lower(player.PlayerName) == string.lower(name) and player.Human then
                        targID = player.OwnerID
                        break
                    end
                end                
                if targID then
                    PrivateChat(targID, string.sub(params, delimStart+1))
                else
                    AddChatText(LOC("<LOC lobby_0007>Invalid whisper target."))
                end
            end
        end,

        ban = function(self, params) -- [?playername] [?reason]
            if lobbyComm:IsHost() then
                local name = params
                local reason = ""
                local delimStart = string.find(params, " ")
                if delimStart then
                    name = string.sub(params, 1, delimStart-1)
                    reason = string.sub(params, delimStart+1)
                end
                if name == "" then
                    AddChatText("Banned players : ")
                    for n,r in pairs(self.PlayerFilters.BannedPlayers) do 
                        AddChatText("- " .. n .. " : " .. r)
                    end
                else
                    local txt = name .. " has been banned."
                    AddChatText(txt .. " Reason : " .. reason)

                    lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    self.PlayerFilters.BannedPlayers[string.lower(name)] = reason
                    self.PlayerFilters.KickPlayerByName(name, reason)
                end
            else
                AddChatText("Only the host can use that command")
            end
        end,

        unban = function(self, params)  -- [?playername]
            if lobbyComm:IsHost() then
                local name = params
                local delimStart = string.find(params, " ")
                if delimStart then
                    name = string.sub(params, 1, delimStart-1)
                end
                if name == "" then
                    local txt = "All banned players have benn unbanned."
                    AddChatText(txt)
                    lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    for n, r in pairs(self.PlayerFilters.BannedPlayers) do self.PlayerFilters.BannedPlayers[n] = nil end
                else
                    local txt = name .. " has been unbanned."
                    AddChatText(txt)
                    lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    self.PlayerFilters.BannedPlayers[string.lower(name)] = nil
                end
            else
                AddChatText("Only the host can use that command")
            end
        end,

        cpuscores = function(self, params) -- [value]
            local delimStart = string.find(params, " ")
            if delimStart then
                params = string.sub(params, 1, delimStart-1)
            end
            local value = tonumber(params)

            if value then
                for name, result in CPU_Benchmarks do
                    CPU_Benchmarks[name] = value
                    if FindObserverSlotForID(name) then
                        refreshObserverList()
                    else
                        UpdateCPUBar(name)
                    end
                end
                lobbyComm:BroadcastData({Type='CPUBenchmark', Benchmarks=CPU_Benchmarks})
                AddChatText("All CPU scores has been set to " .. value)
            else
                AddChatText("Syntax : /cpuscores [value]")
            end
        end,

        cpuscore = function(self, params) -- [?playername] [value]
            local name = localPlayerName
            local value = params
            local delimStart = string.find(params, " ")
            if delimStart then
                name = string.sub(params, 1, delimStart-1)
                value = string.sub(params, delimStart+1)
            end
            value = tonumber(value)
            if value then
                for sname, result in CPU_Benchmarks do
                    if string.lower(sname) == string.lower(name) then
                        CPU_Benchmarks[sname] = value
                        lobbyComm:BroadcastData({ Type = 'CPUBenchmark', PlayerName = sname, Result = value })                
                        if FindObserverSlotForID(sname) then
                            refreshObserverList()
                        else
                            UpdateCPUBar(sname)
                        end
                        AddChatText("The CPU score of " .. sname .. " has been set to " .. value)
                        return
                    end
                end
                AddChatText("The player " .. name .. " was not found")
            else
                AddChatText("Syntax : /cpuscore [?playername] [value]")
            end
        end,

        cpulimit = function(self, params) -- [?max]
            if lobbyComm:IsHost() then
                if params ~= "" then
                    local value = tonumber(params)
                    if value then
                        self.PlayerFilters.MaxCpu = value
                        local txt = "Max CPU score limit has been set to " .. value
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                        self.PlayerFilters:Filter()
                    else
                        AddChatText("Syntax : /cpulimit [?max]")
                    end
                else
                    self.PlayerFilters.MaxCpu = 1000
                    local txt = "The CPU score limit has been removed"
                    AddChatText(txt)
                    lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                end
            else
                AddChatText("Only the host can use that command")
            end
        end,

        ranklimit = function(self, params) -- [?min] [?max]
            if lobbyComm:IsHost() then
                if params ~= "" then
                    local min = params
                    local max = 10000
                    local delimStart = string.find(params, " ")
                    if delimStart then
                        min = string.sub(params, 1, delimStart-1)
                        max = string.sub(params, delimStart+1)
                    end
                    min = tonumber(min)
                    max = tonumber(max)
                    if min and max then
                        self.PlayerFilters.MinRank = min
                        self.PlayerFilters.MaxRank = max
                        local txt = "Rank limits has been set to " .. min .. "-" .. max
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                        self.PlayerFilters:Filter()
                    else
                        AddChatText("Syntax : /ranklimit [?min] [?max]")
                    end
                else 
                    self.PlayerFilters.MinRank = -10000
                    self.PlayerFilters.MaxRank = 10000
                    local txt = "The rank limits have been removed"
                    AddChatText(txt)
                    lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                end
            else
                AddChatText("Only the host can use that command")
            end
        end,

        gameslimit = function(self, params) -- [?min] [?max]
            if lobbyComm:IsHost() then
                if params ~= "" then
                    local min = params
                    local max = 100000
                    local delimStart = string.find(params, " ")
                    if delimStart then
                        min = string.sub(params, 1, delimStart-1)
                        max = string.sub(params, delimStart+1)
                    end
                    min = tonumber(min)
                    max = tonumber(max)
                    if min and max then
                        self.PlayerFilters.MinGames = min
                        self.PlayerFilters.MaxGames = max
                        local txt = "Number of games limits has been set to " .. min .. "-" .. max
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                        self.PlayerFilters:Filter()
                    else
                        AddChatText("Syntax : /gameslimit [?min] [?max]")
                    end
                else 
                    self.PlayerFilters.MinGames = 0
                    self.PlayerFilters.MaxGames = 100000
                    local txt = "The number of games limits have been removed"
                    AddChatText(txt)
                    lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                end
            else
                AddChatText("Only the host can use that command")
            end
        end,

        myslot = function(self, params)
            local delimStart = string.find(params, " ")
            if delimStart then
                params = string.sub(params, 1, delimStart-1)
            end
            params = tonumber(params)
            if params then
                MapName = string.gsub(MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile).name, "[ .,]", "_")
                local PreferedSlots = Prefs.GetFromCurrentProfile("PreferedSlots") or {}
                PreferedSlots[MapName] = params
                Prefs.SetToCurrentProfile('PreferedSlots', PreferedSlots)
                AddChatText("Your prefered slot on this map has been set to " .. params)
            else
                AddChatText("Syntax : /myspot [spot number]")
            end
        end,

        info = function(self, params)
            local name = params
            local info = ""
            local delimStart = string.find(params, " ")
            if delimStart then
                name = string.sub(params, 1, delimStart-1)
                info = string.sub(params, delimStart+1)
            end
            local PlayerInfos = Prefs.GetFromCurrentProfile("PlayerInfos") or {}
            if name == "" then
                AddChatText("Connected players informations : ")
                for k, player in gameInfo.PlayerOptions:pairs() do
                    if PlayerInfos[string.lower(player.PlayerName)] then
                        AddChatText("- " .. player.PlayerName .. " : " .. PlayerInfos[string.lower(player.PlayerName)])
                    end
                end        
            elseif name == "all" then
                AddChatText("All players informations : ")
                for n,v in pairs(PlayerInfos) do 
                    AddChatText("- " .. n .. " : " .. v)
                end
            else
                if info == "" then
                    if PlayerInfos[string.lower(name)] then
                        AddChatText("- " .. name .. " : " .. PlayerInfos[string.lower(name)])
                    else
                        AddChatText("No infos for " .. name)
                    end
                else
                    PlayerInfos[string.lower(name)] = info
                    Prefs.SetToCurrentProfile("PlayerInfos", PlayerInfos)
                    AddChatText("Infos for " .. name .. " saved")
                end
            end
        end,

        reminfo = function(self, params)
            local name = params
            local delimStart = string.find(params, " ")
            if delimStart then
                name = string.sub(params, 1, delimStart-1)
            end
            if name == "" then
                AddChatText("Syntax : /reminfo [player name]")
            else
                local PlayerInfos = Prefs.GetFromCurrentProfile("PlayerInfos") or {}
                if PlayerInfos[string.lower(name)] then
                    PlayerInfos[string.lower(name)] = nil;
                    Prefs.SetToCurrentProfile("PlayerInfos", PlayerInfos)
                    AddChatText("Infos for " .. name .. " has been removed")
                else
                    AddChatText("No infos for " .. name)
                end
            end
        end,

        stats = function(self, params)
            local text = "Team stats : " .. self.KyrosLobby.team1RatingSum .. " (" .. self.KyrosLobby.team1GamesSum .. ") VS " .. self.KyrosLobby.team2RatingSum .. " (" .. self.KyrosLobby.team2GamesSum .. ")"
            lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = text,})
            AddChatText(text)
        end,

        help = function(self, params)
            AddChatText("Welcome to KyrO's Lobby!")
            AddChatText("This lists all available commands (parameters with ? are optional).")
            AddChatText("- /help : Displays this")
            AddChatText("- /pm [playername] : Sends a private message (/pm KyrO Hello)")
            AddChatText("- /stats : Displays the total rating and number of games of both teams to everyone")
            AddChatText("- /myslot [slotnbr] : Saves your prefered slot on this map. You will be moved to this slot (if available) as soon as you join a lobby with this map (/myslot 12)")
            AddChatText("- /ban [playername] [reason?] : Bans a player. This player will be auto-kicked if he tries to join the lobby (/ban KyrO I don't like you)")
            AddChatText("- /ban : Lists all banned players")
            AddChatText("- /unban [playername] : Unbans a player")
            AddChatText("- /unban : Unbans all players")
            AddChatText("- /cpulimit [max] : Auto-kicks all players who have a higher cpu score than the provided value (/cpulimit 250)")
            AddChatText("- /cpulimit : Removes the cpu limit")
            AddChatText("- /ranklimit [min] [max] : Auto-kicks all players who do not have a rating between the provided values (/ranklimit 800 1600)")
            AddChatText("- /ranklimit : Removes the rank limit")
            AddChatText("- /gameslimit [min] [max] : Auto-kicks all players who do not have a number of games between the provided values (/gameslimit 100 10000)")
            AddChatText("- /gameslimit : Removes the number of games limit")
            AddChatText("- /info [playername] [text] : Saves a comment about a player (/info KyrO Slow cpu)")
            AddChatText("- /info [playername] : Displays the comment about a player")
            AddChatText("- /info : Displays the comments of all connected players")
            AddChatText("- /info all : Displays all saved comments")
            AddChatText("- /reminfo [playername] : Removes the comment about a player")
        end,

    },

    -- Filter and auto-kick joining players
    -- Place KyrosLobby.PlayerFilters:Filter() at the end of lobbyComm.DataReceived > elseif data.Type == 'CPUBenchmark' then 
    -- Playce KyrosLobby.PlayerFilters:Filter(playerData) at the end of InitHostUtils() > HostUtils > TryAddPlayer
    PlayerFilters = {
        BannedPlayers = {},
        MaxCpu = 1000,
        MinRank = -10000,
        MaxRank = 10000,
        MinGames = 0,
        MaxGames = 100000,

        Filter = function(self, playerData)
            -- Only the host can kick players
            if lobbyComm:IsHost() then
                if playerData then
                    -- Filter the specified player
                    if self.BannedPlayers[string.lower(playerData.PlayerName)] then
                        self.KickPlayerByName(playerData.PlayerName, "Banned! " .. self.BannedPlayers[string.lower(playerData.PlayerName)])
                        local txt = playerData.PlayerName .. " has been auto-kicked because he is banned"
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    elseif playerData.NG < self.MinGames then
                        self.KickPlayerByName(playerData.PlayerName, "Your number of games is too low. Minimum number of games is " .. self.MinGames)
                        local txt = playerData.PlayerName .. " has been auto-kicked because his number of games is too low (he has " .. playerData.NG .. " and min is " .. self.MinGames .. ")"
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    elseif playerData.NG > self.MaxGames then
                        self.KickPlayerByName(playerData.PlayerName, "Your number of games is too high. Maximum number of games is " .. self.MaxGames)
                        local txt = playerData.PlayerName .. " has been auto-kicked because his number of games is too high (he has " .. playerData.NG .. " and max is " .. self.MaxGames .. ")"
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    elseif playerData.PL < self.MinRank then
                        self.KickPlayerByName(playerData.PlayerName, "Your rank is too low. Minimum rank is  " .. self.MinRank)
                        local txt = playerData.PlayerName .. " has been auto-kicked because his rank is too low (he has " .. playerData.PL .. " and min is " .. self.MinRank .. ")"
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    elseif playerData.PL > self.MaxRank  then
                        self.KickPlayerByName(playerData.PlayerName, "Your rank is too high. Maximum rank is " .. self.MaxRank)
                        local txt = playerData.PlayerName .. " has been auto-kicked because his rank is too high (he has " .. playerData.PL .. " and max is " .. self.MaxRank .. ")"
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    elseif CPU_Benchmarks[playerData.PlayerName] and CPU_Benchmarks[playerData.PlayerName] > self.MaxCpu then
                        self.KickPlayerByName(playerData.PlayerName, "Your CPU score is to high. Maximum CPU score is " .. self.MaxCpu)
                        local txt = playerData.PlayerName .. " has been auto-kicked because his cpu score is too high (he has " .. CPU_Benchmarks[playerData.PlayerName] .. " and max is " .. self.MaxCpu .. ")"
                        AddChatText(txt)
                        lobbyComm:BroadcastData({Type = "PublicChat", SenderName = "", Text = txt,})
                    end
                else
                    -- Filter all players
                    for k, player in gameInfo.PlayerOptions:pairs() do
                        if player.Human and player.PlayerName ~= localPlayerName then
                            self:Filter(player)
                        end
                    end
                end
            end
        end,

        KickPlayerByName = function(name, reason)
            for k, player in gameInfo.PlayerOptions:pairs() do
                if string.lower(player.PlayerName) == string.lower(name) and player.Human then
                    lobbyComm:EjectPeer(player.OwnerID, "\n You have been auto-kicked from this lobby! \n Reason: " .. reason)
                    return 
                end
            end
        end,

    },
}
KyrosLobby.Commands.PlayerFilters = KyrosLobby.PlayerFilters
KyrosLobby.Commands.KyrosLobby = KyrosLobby


-- Remove 	function setupChatEdit(chatPanel)
-- Remove     -- set up chat display
-- Replace GUI.chatPanel
ChatBox = Class(Group) {
    ChatEdit = false,
    ChatList = false,

    __init = function(self, Parent, Options)
        Group.__init(self, Parent)

        -- Properties init
        if not Options then Options = {} end

        -- Edit background
        self.EditBackground = Bitmap(self)
        self.EditBackground:SetSolidColor('FF212123')
        self.EditBackground.Left:Set(function() return self.Left() end)
        self.EditBackground.Right:Set(function() return self.Right() end) 
        self.EditBackground.Bottom:Set(function() return self.Bottom() end)
        self.EditBackground.Height:Set(25)

        -- Edit
        self.ChatEdit = Edit(self)
        self.ChatEdit.Left:Set(function() return self.Left() + 1 end)
        self.ChatEdit.Width:Set(function() return self.Width() - 2 end) 
        self.ChatEdit.Bottom:Set(function() return self.Bottom() end)
        self.ChatEdit.Height:Set(function() return self.EditBackground.Height() - 3 end)
        self:SetupEdit()
        self.ChatEdit.Depth:Set(function() return self.EditBackground.Depth() + 10 end)

        -- Messages List
        self.ChatList = RichTextBox(self, Options)
        self.ChatList.Width:Set(function() return self.Width() end)
        self.ChatList.Height:Set(function() return self.Height() - self.EditBackground.Height() end)
        self.ChatList.Left:Set(function() return self.Left() end)
        self.ChatList.Top:Set(function() return self.Top() end)        
        self.ChatList.DefaultTextOptions.FontName = UIUtil.bodyFont
        self.ChatList.DefaultTextOptions.FontSize = tonumber(Prefs.GetFromCurrentProfile('LobbyChatFontSize')) or 14
        self.ChatList.DefaultTextOptions.ForeColor = UIUtil.fontColor
        self.ChatList.DefaultTextOptions.DropShadow = true


    end,

    KeepFocus = function(self, value) 
        self._focus = value
        if value then 
            self.ChatEdit:AcquireFocus() 
        else
            self.ChatEdit:AbandonFocus()
        end
    end,

    SetupEdit = function(self)

        --self.ChatEdit:SetFont("Arial Gras", 12) -- Must be called after Edit's Width has been set !!   - UIUtil.bodyFont    
        self.ChatEdit:SetForegroundColor(UIUtil.fontColor) -- UIUtil.fontColor
        self.ChatEdit:ShowBackground(false)
        self.ChatEdit:SetDropShadow(true)
        self.ChatEdit:SetMaxChars(200)
        self:KeepFocus(true)


        self.ChatEdit.OnCharPressed = function(self, charcode)
            if charcode == UIUtil.VK_TAB then
                return true
            end
            local charLim = self:GetMaxChars()
            if STR_Utf8Len(self:GetText()) >= charLim then
                local sound = Sound({Cue = 'UI_Menu_Error_01', Bank = 'Interface',})
                PlaySound(sound)
            end
        end

        -- We work extremely hard to keep keyboard focus on the chat box, otherwise users can trigger
        -- in-game keybindings in the lobby.
        -- That would be very bad. We should probably instead just not assign those keybindings yet...
        self.ChatEdit.OnLoseKeyboardFocus = function(self2)
            if self._focus then        
                self2:AcquireFocus()
            end
        end

        local commandQueueIndex = 0
        local commandQueue = {}
        self.ChatEdit.OnEnterPressed = function(self2, text)
            if text ~= "" then
                GpgNetSend('Chat', text)
                table.insert(commandQueue, 1, text)
                commandQueueIndex = 0
                if not KyrosLobby.Commands:Handle(text) then
                    lobbyComm:BroadcastData({Type = "PublicChat", Text = text,})
                    self:AppendPlayerMessage(localPlayerName, text)
                end
            end
        end

        self.ChatEdit.OnEscPressed = function(self, text)
            GUI.exitLobbyEscapeHandler()
            -- Don't clear the textbox, either.
            return true
        end

        --- Handle up/down arrow presses for the chat box.
        self.ChatEdit.OnNonTextKeyPressed = function(self, keyCode)
            if AddUnicodeCharToEditText(self, keyCode) then
                return
            end
            if commandQueue and table.getsize(commandQueue) > 0 then
                if keyCode == 38 then
                    if commandQueue[commandQueueIndex + 1] then
                        commandQueueIndex = commandQueueIndex + 1
                        self:SetText(commandQueue[commandQueueIndex])
                    end
                end
                if keyCode == 40 then
                    if commandQueueIndex ~= 1 then
                        if commandQueue[commandQueueIndex - 1] then
                            commandQueueIndex = commandQueueIndex - 1
                            self:SetText(commandQueue[commandQueueIndex])
                        end
                    else
                        commandQueueIndex = 0
                        self:ClearText()
                    end
                end
            end
        end
    end,

    AppendText = function(self, Message, NewLine, TextOptions, LineOptions)
        local IsScrolledToBottom = self.ChatList:IsScrolledToBottom()
        self.ChatList:AppendText(Message, NewLine, TextOptions, LineOptions)
        if IsScrolledToBottom then self.ChatList:ScrollToBottom() end
    end,

    AppendLine = function(self, Message, TextOptions, LineOptions)
        self:AppendText(Message, true, TextOptions, LineOptions)
    end,

    AppendSystemInfo = function(self, Message) 
        self:AppendText(Message, true, {ForeColor="ff777777"})
    end,

    AppendSystemError = function(self, Message) 
        self:AppendText(Message, true, {ForeColor="ffff0000"})
    end,

    AppendPrivateMessage = function(self, PlayerName, DestinationPlayer, Message)
        self:AppendPlayerMessage(PlayerName, "<< To " .. DestinationPlayer .. " >> " .. Message)
    end,

    AppendPlayerMessage = function(self, PlayerName, Message)

        local Player = false
        -- Find the PlayerName in the slots
        for k, p in gameInfo.PlayerOptions:pairs() do
            if p.PlayerName == PlayerName and p.Human then
                Player = p
            end
        end
        -- If the player was found, get his color.
        local PlayerColor = false
        if not Player then
            PlayerColor = "ffffffff"
        else
            PlayerColor = gameColors.PlayerColors[Player.PlayerColor]
        end

        self:AppendText(PlayerName, true, {FontName = "Arial Gras", ForeColor = PlayerColor}, {Padding = {3,0,0,0}})

        -- Host slot color : ffc726 
        -- Own slot color : 6363d2

        -- Find the PlayerName in the observers
        if not Player then
            for k, observer in gameInfo.Observers:pairs() do
                if observer.PlayerName == PlayerName then
                    Player = observer
                end
            end
        end
        -- Test if Player is the local player or the host
        if not Player then
            -- Should not happen
            self:AppendText(Message, false, {ForeColor = "ff666666"})
        elseif Player.OwnerID == localPlayerID then
            -- Own message = light blue
            self:AppendText(Message, false, {ForeColor = "ff6666FF"})
        elseif Player.OwnerID == hostID then
            -- Host message = white
            self:AppendText(Message, false, {ForeColor = "ffffffff"})
        else
            -- Normal player message
            self:AppendText(Message, false)
        end
    end,

    Refresh = function(self)
        self.ChatList:Refresh()
    end,

}

-- String from which to build the various "Move player to slot" labels.
local slotMenuStrings = {
    open = "<LOC lobui_0219>Open",
    close = "<LOC lobui_0220>Close",
    closed = "<LOC lobui_0221>Closed",
    occupy = "<LOC lobui_0222>Occupy",
    pm = "<LOC lobui_0223>Private Message",
    remove_to_kik = "<LOC lobui_0428>Kick Player",
    remove_to_observer = "<LOC lobui_0429>Move Player to Observer",
    close_spawn_mex = "<LOC lobui_0431>Close - spawn mex",
    closed_spawn_mex = "<LOC lobui_0432>Closed - spawn mex",
}
local slotMenuData = {
    open = {
        host = {
            'close',
            'occupy',
            'ailist',
        },
        client = {
            'occupy',
        },
    },
    closed = {
        host = {
            'open',
        },
        client = {
        },
    },
    player = {
        host = {
            'pm',
            'remove_to_observer',
            'remove_to_kik',
            'move'
        },
        client = {
            'pm',
        },
    },
    ai = {
        host = {
            'remove_to_kik',
            'ailist',
        },
        client = {
        },
    },
}

local function GetSlotMenuData()
    if gameInfo.AdaptiveMap then
        if not slotMenuData.closed_spawn_mex then
            slotMenuData.closed_spawn_mex = {
                                                    host = {
                                                        'open',
                                                        'close',
                                                    },
                                                    client = {
                                                    },
                                                }
            table.insert(slotMenuData.open.host, 2, 'close_spawn_mex')
            table.insert(slotMenuData.closed.host, 2, 'close_spawn_mex')
        end
    else
        if slotMenuData.closed_spawn_mex then
            slotMenuData.closed_spawn_mex = nil
            table.remove(slotMenuData.open.host, 2)
            table.remove(slotMenuData.closed.host, 2)
        end
    end
    return slotMenuData
end

local function GetSlotMenuTables(stateKey, hostKey, slotNum)
    local keys = {}
    local strings = {}
    local tooltips = {}

    if not GetSlotMenuData()[stateKey] then
        WARN("Invalid slot menu state selected: " .. stateKey)
        return nil
    end

    if not GetSlotMenuData()[stateKey][hostKey] then
        WARN("Invalid slot menu host key selected: " .. hostKey)
        return nil
    end

    local isPlayerReady = false
    local localPlayerSlot = FindSlotForID(localPlayerID)
    if localPlayerSlot then
        if gameInfo.PlayerOptions[localPlayerSlot].Ready then
            isPlayerReady = true
        end
    end

    for index, key in GetSlotMenuData()[stateKey][hostKey] do
        if key == 'ailist' then
            if slotNum then
                for i = 1, numOpenSlots, 1 do
                    if i ~= slotNum then
                        table.insert(keys, 'move_player_to_slot' .. i)
                        table.insert(strings, LOCF("<LOC lobui_0607>Move AI to slot %s", i))
                        table.insert(tooltips, nil)
                    end
                end
            end
            for aiindex, aidata in aitypes do
                table.insert(keys, aidata.key)
                table.insert(strings, aidata.name)
                table.insert(tooltips, 'aitype_'..aidata.key)
            end
        elseif key == 'move' then
            -- Generate the "move player to slot X" entries.
            for i = 1, numOpenSlots, 1 do
                if i ~= slotNum then
                    table.insert(keys, 'move_player_to_slot' .. i)
                    table.insert(strings, LOCF("<LOC lobui_0596>Move Player to slot %s", i))
                    table.insert(tooltips, nil)
                end
            end
        else
            if not (isPlayerReady and key == 'occupy') then
                table.insert(keys, key)
                table.insert(strings, slotMenuStrings[key])
                -- Add a tooltip key here if we ever get any interesting options.
                table.insert(tooltips, nil)
            end
        end
    end

    return keys, strings, tooltips
end

--- Get the value of the LastColor, sanitised in case it's an unsafe value.
-- In case a new patch removes a color
function GetSanitisedLastColor()
    local lastColor = Prefs.GetFromCurrentProfile('LastColorFAF') or 1
    if lastColor > table.getn(gameColors.PlayerColors) or lastColor < 1 then
        lastColor = 1
    end

    return lastColor
end

--- Get the value of the LastFaction, sanitised in case it's an unsafe value.
--
-- This means when some retarded mod (*cough*Nomads*cough*) writes a large number to LastFaction, we
-- don't catch fire.
function GetSanitisedLastFaction()
    local lastFaction = Prefs.GetFromCurrentProfile('LastFaction') or 1
    if lastFaction > table.getn(FactionData.Factions) + 1 or lastFaction < 1 then
        lastFaction = 1
    end

    return lastFaction
end

--- Get a PlayerData object for the local player, configured using data from their profile.
function GetLocalPlayerData()
    return PlayerData(
        {
            PlayerName = localPlayerName,
            OwnerID = localPlayerID,
            Human = true,
            PlayerColor = GetSanitisedLastColor(),
            Faction = GetSanitisedLastFaction(),
            PlayerClan = argv.playerClan,
            PL = playerRating,
            NG = argv.numGames,
            MEAN = argv.playerMean,
            DEV = argv.playerDeviation,
            Country = argv.PrefLanguage,
        }
)
end

function GetAIPlayerData(name, AIPersonality)
    return PlayerData(
        {
            OwnerID = hostID,
            PlayerName = name,
            Ready = true,
            Human = false,
            AIPersonality = AIPersonality,
        }
)
end

function DoSlotBehavior(slot, key, name)
    if key == 'open' then
        HostUtils.SetSlotClosed(slot, false)
    elseif key == 'close' then
        HostUtils.SetSlotClosed(slot, true)
    elseif key == 'close_spawn_mex' then
        HostUtils.SetSlotClosedSpawnMex(slot)
    elseif key == 'occupy' then
        if IsPlayer(localPlayerID) and not gameInfo.PlayerOptions[FindSlotForID(localPlayerID)].Ready then
            if lobbyComm:IsHost() then
                HostUtils.MovePlayerToEmptySlot(FindSlotForID(localPlayerID), slot)
            else
                lobbyComm:SendData(hostID, {Type = 'MovePlayer', RequestedSlot = slot})
            end
        elseif IsObserver(localPlayerID) then
            if lobbyComm:IsHost() then
                local requestedFaction = GetSanitisedLastFaction()
                HostUtils.ConvertObserverToPlayer(FindObserverSlotForID(localPlayerID), slot)
            else
                lobbyComm:SendData(
                    hostID,
                    {
                        Type = 'RequestConvertToPlayer',
                        ObserverSlot = FindObserverSlotForID(localPlayerID),
                        PlayerSlot = slot
                    }
                )
            end
        end
        UpdateFactionSelector()
    elseif key == 'pm' then
        if gameInfo.PlayerOptions[slot].Human then
            GUI.chatDisplay.ChatEdit:SetText(string.format("/whisper %s ", gameInfo.PlayerOptions[slot].PlayerName))
        end
    -- Handle the various "Move to slot X" options.
    elseif string.sub(key, 1, 19) == 'move_player_to_slot' then
        HostUtils.SwapPlayers(slot, tonumber(string.sub(key, 20)))
    elseif key == 'remove_to_observer' then
        local playerInfo = gameInfo.PlayerOptions[slot]
        if playerInfo.Human then
            HostUtils.ConvertPlayerToObserver(slot)
        end
    elseif key == 'remove_to_kik' then
        if gameInfo.PlayerOptions[slot].Human then
            local kickMessage = function(self, str)
                local msg

                msg = "\n Kicked by host. \n Reason: " .. str

                SendSystemMessage("lobui_0756", gameInfo.PlayerOptions[slot].PlayerName)
                lobbyComm:EjectPeer(gameInfo.PlayerOptions[slot].OwnerID, msg)

                -- Save message for next time
                Prefs.SetToCurrentProfile('lastKickMessage', str)
                lastKickMessage = str
            end

            CreateInputDialog(GUI, "<LOC lobui_0166>Are you sure?", kickMessage, lastKickMessage)
        else
            HostUtils.RemoveAI(slot)
        end
    else
        -- We're adding an AI of some sort.
        if lobbyComm:IsHost() then
            HostUtils.AddAI(name, key, slot)
        end
    end
end

local function IsModAvailable(modId)
    for k,v in availableMods do
        if not v[modId] then
            return false
        end
    end
    return true
end


function Reset()
    lobbyComm = false
    localPlayerName = ""
    gameName = ""
    hostID = false
    singlePlayer = false
    GUI = false
    localPlayerID = false
    availableMods = {}
    selectedUIMods = Mods.GetSelectedUIMods()
    selectedSimMods = Mods.GetSelectedSimMods()
    numOpenSlots = LobbyComm.maxPlayerSlots
    gameInfo = GameInfo.CreateGameInfo(LobbyComm.maxPlayerSlots)
end

--- Create a new, unconnected lobby.
function ReallyCreateLobby(protocol, localPort, desiredPlayerName, localPlayerUID, natTraversalProvider, over, exitBehavior, playerHasSupcom)
    Reset()

    -- Among other things, this clears uimain's override escape handler, allowing our escape
    -- handler manager to work.
    MenuCommon.MenuCleanup()

    if GUI then
        WARN('CreateLobby called twice for UI construction (Should be unreachable)')
        GUI:Destroy()
        return
    end

    -- Make sure we have a profile
    if not GetPreference("profile.current") then
        Prefs.CreateProfile("FAF_"..desiredPlayerName)
    end

    GUI = UIUtil.CreateScreenGroup(over, "CreateLobby ScreenGroup")

    GUI.exitBehavior = exitBehavior

    GUI.optionControls = {}
    GUI.slots = {}

    -- Set up the base escape handler first: want this one at the bottom of the stack.
    GUI.exitLobbyEscapeHandler = function()
        GUI.chatDisplay:KeepFocus(false)
        local quitDialog = UIUtil.QuickDialog(GUI,
            "<LOC lobby_0000>Exit game lobby?",
            "<LOC _Yes>", function()
                EscapeHandler.PopEscapeHandler()
                if HasCommandLineArg("/gpgnet") then
                    -- Quit to desktop
                    EscapeHandler.SafeQuit()
                else
                    -- Back to main menu
                    ReturnToMenu(false)
                end
            end,

            -- Fight to keep our focus on the chat input box, to prevent keybinding madness.
            "<LOC _Cancel>", function()
                GUI.chatDisplay:KeepFocus(true)
            end,
            nil, nil,
            true
        )
    end
    EscapeHandler.PushEscapeHandler(GUI.exitLobbyEscapeHandler)

    GUI.connectdialog = UIUtil.ShowInfoDialog(GUI, Strings.TryingToConnect, Strings.AbortConnect, ReturnToMenu)
    -- Prevent the dialog from being closed due to user action.
    GUI.connectdialog.OnEscapePressed = function() end
    GUI.connectdialog.OnShadowClicked = function() end

    InitLobbyComm(protocol, localPort, desiredPlayerName, localPlayerUID, natTraversalProvider)

    -- Store off the validated playername
    localPlayerName = lobbyComm:GetLocalPlayerName()
    local Prefs = import('/lua/user/prefs.lua')
    local windowed = Prefs.GetFromCurrentProfile('WindowedLobby') or 'false'
    SetWindowedLobby(windowed == 'true')

end

-- A map from message types to functions that process particular message types.
local MESSAGE_HANDLERS = {
    -- TODO: Finalise signature and semantics.
    ConnectivityState = function()
    end
}

--- Handle an incoming message from the FAF client via the GPGNet protocol.
--
-- @param jsonBlob A JSON string containing the message to process.
-- Messages are JSON strings containing two fields:
-- command_id: A string identifying the type of message. This string is used as a key into
--             MESSAGE_HANDLERS to find the function to use to process this message.
-- arguments: An array of arguments that should be passed to the handler function.
function HandleGPGNetMessage(jsonBlob)
    local jsonObj = JSON.decode(jsonBlob)
    table.print(jsonObj)
    local handler = MESSAGE_HANDLERS[jsonObj.command_id]
    if not handler then
        WARN("Incomprehensible JSON message: \n" .. jsonBlob)
        return
    end

    handler(unpack(jsonObj.arguments))
end

--- Start a synchronous replay session
--
-- @param replayID The ID of the replay to download and play.
function StartSyncReplaySession(replayID)
    SetFrontEndData('syncreplayid', replayID)
    local dl = UIUtil.QuickDialog(GetFrame(0), "Downloading the replay file...")
    LaunchReplaySession('gpgnet://' .. GetCommandLineArg('/gpgnet',1)[1] .. '/' .. import('/lua/user/prefs.lua').GetFromCurrentProfile('Name'))
    dl:Destroy()
    UIUtil.QuickDialog(GetFrame(0), "You dont have this map.", "Exit", function() ExitApplication() end)
end

--- Create a new unconnected lobby/Entry point for processing messages sent from the FAF lobby.
--
-- This function is called exactly once by the game when a new lobby should be created.
-- @see ReallyCreateLobby
--
-- This function is called whenever the FAF lobby sends a message into the game, with the message
-- in the desiredPlayerName parameter as a JSON string with a length no greater than 4061 bytes.
-- This madness is justified by this being one of the smallish number of functions we can have
-- called from outside.
-- @see HandleGPGNetMessage
--
-- This function is also called by the sync replay server when a session should be started. (this
-- should probably be refactored to use the JSON messenger protocol)
-- @see StartSyncReplaySession
function CreateLobby(protocol, localPort, desiredPlayerName, localPlayerUID, natTraversalProvider, over, exitBehavior, playerHasSupcom)
    -- Is this an incoming GPGNet message?
    if localPort == -1 then
        HandleGPGNetMessage(desiredPlayerName)
        return
    end

    -- Special-casing for sync-replay.
    -- TODO: Consider replacing this with a gpgnet message type.
    if IsSyncReplayServer then
        StartSyncReplaySession(localPlayerUID)
        return
    end

    -- Okay, so we actually are creating a lobby, instead of doing some ridiculous hack.
    ReallyCreateLobby(protocol, localPort, desiredPlayerName, localPlayerUID, natTraversalProvider, over, exitBehavior, playerHasSupcom)
end

-- create the lobby as a host
function HostGame(desiredGameName, scenarioFileName, inSinglePlayer)
    singlePlayer = inSinglePlayer
    gameName = lobbyComm:MakeValidGameName(desiredGameName)
    lobbyComm.desiredScenario = string.gsub(scenarioFileName, ".v%d%d%d%d_scenario.lua", "_scenario.lua")
    lobbyComm:HostGame()
end

-- join an already existing lobby
function JoinGame(address, asObserver, playerName, uid)
    lobbyComm:JoinGame(address, playerName, uid)
end

function ConnectToPeer(addressAndPort,name,uid)
    if not string.find(addressAndPort, '127.0.0.1') then
        LOG("ConnectToPeer (name=" .. name .. ", uid=" .. uid .. ", address=" .. addressAndPort ..")")
    else
        DisconnectFromPeer(uid)
        LOG("ConnectToPeer (name=" .. name .. ", uid=" .. uid .. ", address=" .. addressAndPort ..", USE PROXY)")
        table.insert(ConnectedWithProxy, uid)
    end
    lobbyComm:ConnectToPeer(addressAndPort,name,uid)
end

function DisconnectFromPeer(uid)
    LOG("DisconnectFromPeer (uid=" .. uid ..")")
    if wasConnected(uid) then
        table.remove(connectedTo, uid)
    end
    GpgNetSend('Disconnected', string.format("%d", uid))
    lobbyComm:DisconnectFromPeer(uid)
end

function SetHasSupcom(cmd)
    -- TODO: Refactor SyncReplayServer gubbins to use generalised JSON protocol.
    if IsSyncReplayServer then
        if cmd == 0 then
            SessionResume()
        elseif cmd == 1 then
            SessionRequestPause()
        end
    end
end

function SetHasForgedAlliance(speed)
    if IsSyncReplayServer then
        if GetGameSpeed() ~= speed then
            SetGameSpeed(speed)
        end
    end
end

-- TODO: These functions are dumb. We have these things called "hashmaps".
function FindSlotForID(id)
    for k, player in gameInfo.PlayerOptions:pairs() do
        if player.OwnerID == id and player.Human then
            return k
        end
    end
    return nil
end

function FindRehostSlotForID(id)
    for index, player in ipairs(rehostPlayerOptions) do
        if player.OwnerID == id and player.Human then
            return player.StartSpot
        end
    end
    return nil
end

function FindNameForID(id)
    if (IsObserver(id)) then
        return (FindObserverNameForID(id))
    end

    for k, player in gameInfo.PlayerOptions:pairs() do
        if player.OwnerID == id and player.Human then
            return player.PlayerName
        end
    end
    return nil
end

function FindIDForName(name)
    for k, player in gameInfo.PlayerOptions:pairs() do
        if player.PlayerName == name and player.Human then
            return player.OwnerID
        end
    end
    return nil
end

function FindObserverSlotForID(id)
    for k, observer in gameInfo.Observers:pairs() do
        if observer.OwnerID == id then
            return k
        end
    end

    return nil
end

function FindObserverNameForID(id)
    for k, observer in gameInfo.Observers:pairs() do
        if observer.OwnerID == id then
            return observer.PlayerName
        end
    end
    return nil
end

function IsLocallyOwned(slot)
    return gameInfo.PlayerOptions[slot].OwnerID == localPlayerID
end

function IsPlayer(id)
    return FindSlotForID(id) ~= nil
end

function IsObserver(id)
    return FindObserverSlotForID(id) ~= nil
end

function UpdateSlotBackground(slotIndex)
    if gameInfo.ClosedSlots[slotIndex] then
        GUI.slots[slotIndex].SlotBackground:SetTexture(UIUtil.UIFile('/SLOT/slot-dis.dds'))
    else
        if gameInfo.PlayerOptions[slotIndex] then
            GUI.slots[slotIndex].SlotBackground:SetTexture(UIUtil.UIFile('/SLOT/slot-player.dds'))
        else
            GUI.slots[slotIndex].SlotBackground:SetTexture(UIUtil.UIFile('/SLOT/slot-player_other.dds'))
        end
    end
end

function GetPlayerDisplayName(playerInfo)
    local playerName = playerInfo.PlayerName
    local displayName = ""
    if playerInfo.PlayerClan ~= "" then
        return string.format("[%s] %s", playerInfo.PlayerClan, playerInfo.PlayerName)
    else
        return playerInfo.PlayerName
    end
end

--- Players with a higher deviation have their rating colour tarnished, to make smurfs easier to
-- detect.
function GetRatingColour(deviation)
    if deviation < 100 then
        return "ffffffff"
    end

    if deviation > 150 then
        return "ff333333"
    end

    -- Linear scale of greyness in between.

    -- Fraction of the way between 100 and 150 we are.
    local greynessFraction = (deviation - 100) / 50

    -- Grey colour value we want (value between 0 and 255). 51 is 0x33.
    local greyness = 51 + (1 - greynessFraction) * 204

    -- Shoehorn that into a colour value string. Madly, because Lua.
    local value = string.format('%02x', greyness)
    return "ff" .. value .. value .. value
end

local WVT = import('/lua/ui/lobby/data/watchedvalue/watchedvaluetable.lua')

-- update the data in a player slot
-- TODO: With lazyvars, this function should be eliminated. Lazy-value-callbacks should be used
-- instead to incrementaly update things.
function SetSlotInfo(slotNum, playerInfo)
    -- Remove the ConnectDialog. It probably makes more sense to do this when we get the game state.
    if GUI.connectdialog then
        GUI.connectdialog:Close()
        GUI.connectdialog = nil

        -- Changelog, if necessary.
        if Changelog.NeedChangelog() then
            Changelog.CreateUI(GUI)
        end
    end

    playerInfo.StartSpot = slotNum

    local slot = GUI.slots[slotNum]
    local isHost = lobbyComm:IsHost()
    local isLocallyOwned = IsLocallyOwned(slotNum)

    -- Set enabledness of controls according to host privelage etc.
    -- Yeah, we set it twice. No, it's not brilliant. Blurgh.
    local facColEnabled = isLocallyOwned or (isHost and not playerInfo.Human)
    UIUtil.setEnabled(slot.faction, facColEnabled)
    UIUtil.setEnabled(slot.color, facColEnabled)

    -- Possibly override it due to the ready box.
    if isLocallyOwned then
        if playerInfo.Ready and playerInfo.Human then
            DisableSlot(slotNum, true)
        else
            EnableSlot(slotNum)
        end
    else
        DisableSlot(slotNum)
    end

    --- Returns true if the team selector for this slot should be enabled.
    --
    -- The predicate was getting unpleasantly long to read.
    local function teamSelectionEnabled(autoTeams, ready, locallyOwned, isHost)
        -- If autoteams has control, no selector for you.
        if autoTeams ~= 'none' then
            return false
        end

        if isHost and not playerInfo.Human then
            return true
        end

        -- You can control your own one when you're not ready.
        if locallyOwned then
            return not ready
        end

        if isHost then
            -- The host can control the team of others, provided he's not ready himself.
            local slot = FindSlotForID(localPlayerID)
            local is_ready = slot and gameInfo.PlayerOptions[slot].Ready -- could be observer

            return not is_ready
        end
    end

    -- Disable team selection if "auto teams" is controlling it. Moderatelty ick.
    local autoTeams = gameInfo.GameOptions.AutoTeams
    UIUtil.setEnabled(slot.team, teamSelectionEnabled(autoTeams, playerInfo.Ready, isLocallyOwned, isHost))

    local hostKey
    if isHost then
        hostKey = 'host'
    else
        hostKey = 'client'
    end

    -- These states are used to select the appropriate strings with GetSlotMenuTables.
    local slotState
    if not playerInfo.Human then
        slot.ratingText:Hide()
        slotState = 'ai'
    elseif not isLocallyOwned then
        slotState = 'player'
    else
        slotState = nil
    end

    slot.name:ClearItems()

    if slotState then
        slot.name:Enable()
        local slotKeys, slotStrings, slotTooltips = GetSlotMenuTables(slotState, hostKey, slotNum)
        slot.name.slotKeys = slotKeys

        if table.getn(slotKeys) > 0 then
            slot.name:AddItems(slotStrings)
            slot.name:Enable()
            Tooltip.AddComboTooltip(slot.name, slotTooltips)
        else
            slot.name.slotKeys = nil
            slot.name:Disable()
            Tooltip.RemoveComboTooltip(slot.name)
        end
    else
        -- no slotState indicate this must be ourself, and you can't do anything to yourself
        slot.name.slotKeys = nil
        slot.name:Disable()
    end

    slot.ratingText:Show()
    slot.ratingText:SetText(playerInfo.PL)
    slot.ratingText:SetColor(GetRatingColour(playerInfo.DEV))

    -- dynamic tooltip to show rating and deviation for each player
    local tooltipText = {}
    tooltipText['text'] = "Rating"
    tooltipText['body'] = LOCF("<LOC lobui_0768>%s's TrueSkill Rating is %s +/- %s", playerInfo.PlayerName, math.round(playerInfo.MEAN), math.ceil(playerInfo.DEV * 3))
    slot.tooltiprating = Tooltip.AddControlTooltip(slot.ratingText, tooltipText)

    slot.numGamesText:Show()
    slot.numGamesText:SetText(playerInfo.NG)

    slot.name:Show()
    -- Change name colour according to the state of the slot.
    if slotState == 'ai' then
        slot.name:SetTitleTextColor("dbdbb9") -- Beige Color for AI
        slot.name._text:SetFont('Arial Gras', 12)
    elseif FindSlotForID(hostID) == slotNum then
        slot.name:SetTitleTextColor("ffc726") -- Orange Color for Host
        slot.name._text:SetFont('Arial Gras', 15)
    elseif slotState == 'player' then
        slot.name:SetTitleTextColor("64d264") -- Green Color for Players
        slot.name._text:SetFont('Arial Gras', 15)
    elseif isLocallyOwned then
        slot.name:SetTitleTextColor("6363d2") -- Blue Color for You
        slot.name._text:SetFont('Arial Gras', 15)
    else
        slot.name:SetTitleTextColor(UIUtil.fontColor) -- Normal Color for Other
        slot.name._text:SetFont('Arial Gras', 12)
    end

    local playerName = playerInfo.PlayerName
    if wasConnected(playerInfo.OwnerID) or isLocallyOwned or not playerInfo.Human then
        slot.name:SetTitleText(GetPlayerDisplayName(playerInfo))
        slot.name._text:SetFont('Arial Gras', 15)
        if not table.find(ConnectionEstablished, playerName) then
            if playerInfo.Human and not isLocallyOwned then
                AddChatText(LOCF("<LOC Engine0004>Connection to %s established.", playerName))

                table.insert(ConnectionEstablished, playerName)
                for k, v in CurrentConnection do
                    if v == playerName then
                        CurrentConnection[k] = nil
                        break
                    end
                end
            end
        end
    else
        slot.name:SetTitleText(LOCF('<LOC Engine0005>Connecting to %s...', playerName))
        slot.name._text:SetFont('Arial Gras', 11)
    end

    slot.faction:Show()

    -- Check if faction is possible for that slot, if not set to random
    -- For example: AIs always start with faction 5, so that needs to be adjusted to fit in slot.Faction
    if table.getn(slot.AvailableFactions) < playerInfo.Faction then
        playerInfo.Faction = table.getn(slot.AvailableFactions)
    end
    slot.faction:SetItem(playerInfo.Faction)

    slot.color:Show()
    Check_Availaible_Color(slotNum)

    slot.team:Show()
    slot.team:SetItem(playerInfo.Team)

    -- Send team data to the server
    if isHost then
        HostUtils.SendPlayerSettingsToServer(slotNum)
    end

    UIUtil.setVisible(slot.ready, playerInfo.Human and not singlePlayer)
    slot.ready:SetCheck(playerInfo.Ready, true)

    if isLocallyOwned and playerInfo.Human then
        Prefs.SetToCurrentProfile('LastColorFAF', playerInfo.PlayerColor)
        Prefs.SetToCurrentProfile('LastFaction', playerInfo.Faction)
    end

    -- Show the player's nationality
    if not playerInfo.Country then
        slot.KinderCountry:Hide()
    else
        slot.KinderCountry:Show()
        slot.KinderCountry:SetTexture(UIUtil.UIFile('/countries/'..playerInfo.Country..'.dds'))

        Tooltip.AddControlTooltip(slot.KinderCountry, {text=LOC("<LOC lobui_0413>Country"), body=LOC(CountryTooltips[playerInfo.Country])})
    end

    UpdateSlotBackground(slotNum)

    -- Set the CPU bar
    SetSlotCPUBar(slotNum, playerInfo)

    ShowGameQuality()
    RefreshMapPositionForAllControls(slotNum)

    if isHost then
        HostUtils.RefreshButtonEnabledness()
    end
end

function ClearSlotInfo(slotIndex)
    local slot = GUI.slots[slotIndex]

    local hostKey
    if lobbyComm:IsHost() then
        GpgNetSend('ClearSlot', slotIndex)
        hostKey = 'host'
    else
        hostKey = 'client'
    end

    local stateKey
    local stateText
    if gameInfo.ClosedSlots[slotIndex] and gameInfo.SpawnMex[slotIndex] and gameInfo.AdaptiveMap then
        stateKey = 'closed_spawn_mex'
        stateText = slotMenuStrings.closed_spawn_mex
    elseif gameInfo.ClosedSlots[slotIndex] then
        gameInfo.SpawnMex[slotIndex] = false
        stateKey = 'closed'
        stateText = slotMenuStrings.closed
    else
        stateKey = 'open'
        stateText = slotMenuStrings.open
    end

    local slotKeys, slotStrings, slotTooltips = GetSlotMenuTables(stateKey, hostKey)

    -- set the text appropriately
    slot.name:ClearItems()
    slot.name:SetTitleText(LOC(stateText))
    if table.getn(slotKeys) > 0 then
        slot.name.slotKeys = slotKeys
        slot.name:AddItems(slotStrings)
        Tooltip.AddComboTooltip(slot.name, slotTooltips)
        slot.name:Enable()
    else
        slot.name.slotKeys = nil
        slot.name:Disable()
        Tooltip.RemoveComboTooltip(slot.name)
    end

    slot.name._text:SetFont('Arial Gras', 12)
    if stateKey == 'closed' then
        slot.name:SetTitleTextColor("Crimson")
    elseif stateKey == 'closed_spawn_mex' then
        slot.name:SetTitleTextColor("2c7f33")
    else
        slot.name:SetTitleTextColor('B9BFB9')
    end

    slot:HideControls()

    UpdateSlotBackground(slotIndex)
    ShowGameQuality()
    RefreshMapPositionForAllControls(slotIndex)
end

function IsColorFree(colorIndex)
    for id, player in gameInfo.PlayerOptions:pairs() do
        if player.PlayerColor == colorIndex then
            return false
        end
    end

    return true
end

function GetPlayerCount()
    local numPlayers = 0
    for k,player in gameInfo.PlayerOptions:pairs() do
        if player then
            numPlayers = numPlayers + 1
        end
    end
    return numPlayers
end

local function GetPlayersNotReady()
    local notReady = false
    for k,v in gameInfo.PlayerOptions:pairs() do
        if v.Human and not v.Ready then
            if not notReady then
                notReady = {}
            end
            table.insert(notReady, v.PlayerName)
        end
    end

    return notReady
end

local function GetRandomFactionIndex(slotNumber)
    local randomfaction = nil
    local counter = 50
    while counter > 0 do
        counter = (counter - 1)
        randomfaction = math.random(1, table.getn(GUI.slots[slotNumber].AvailableFactions) - 1)
    end
    return randomfaction
end

local function AssignRandomFactions()
    for index, player in gameInfo.PlayerOptions do
        -- No random if there is only 1 option
        if table.getn(GUI.slots[index].AvailableFactions) >= 2 then
            local randomFactionID = table.getn(GUI.slots[index].AvailableFactions)
            -- note that this doesn't need to be aware if player has supcom or not since they would only be able to select
            -- the random faction ID if they have supcom
            if player.Faction >= randomFactionID then
                player.Faction = GetRandomFactionIndex(index)
            end
        end
    end
end

-- Convert the local (slot dependend) faction indexes to the global faction indexes
local function FixFactionIndexes()
    for index, player in gameInfo.PlayerOptions do
        local playerFaction = GUI.slots[index].AvailableFactions[player.Faction]
        for i,v in allAvailableFactionsList do
            if v == playerFaction then
                player.Faction = i
                continue
            end
        end
    end

end

---------------------------
-- autobalance functions --
---------------------------
local function team_sort_by_sum(t1, t2)
    return t1['sum'] < t2['sum']
end

local function autobalance_bestworst(players, teams_arg)
    local players = table.deepcopy(players)
    local result = {}
    local best = true
    local teams = {}

    for t, slots in teams_arg do
        table.insert(teams, {team=t, slots=table.deepcopy(slots), sum=0})
    end

    -- teams first picks best player and then worst player, repeat
    while table.getn(players) > 0 do
        for i, t in teams do
            local team = t['team']
            local slots = t['slots']
            local slot = table.remove(slots, 1)
            if not slot then continue end
            local player

            if best then
                player = table.remove(players, 1)
            else
                player = table.remove(players)
            end

            if not player then break end

            teams[i]['sum'] = teams[i]['sum'] + player['rating']
            table.insert(result, {player=player['pos'], rating=player['rating'], team=team, slot=slot})
        end

        best = not best
        if best then
            table.sort(teams, team_sort_by_sum)
        end
    end

    return result
end

local function autobalance_avg(players, teams_arg)
    local players = table.deepcopy(players)
    local result = {}
    local teams = {}
    local max_sum = 0

    for t, slots in teams_arg do
        table.insert(teams, {team=t, slots=table.deepcopy(slots), sum=0})
    end

    while table.getn(players) > 0 do
        local first_team = true
        for i, t in teams do
            local team = t['team']
            local slots = t['slots']
            local slot = table.remove(slots, 1)
            if not slot then continue end
            local player
            local player_key

            for j, p in players do
                player_key = j
                if first_team or t['sum'] + p['rating'] <= max_sum then
                    break
                end
            end

            player = table.remove(players, player_key)
            if not player then break end

            teams[i]['sum'] = teams[i]['sum'] + player['rating']
            max_sum = math.max(max_sum, teams[i]['sum'])
            table.insert(result, {player=player['pos'], rating=player['rating'], team=team, slot=slot})
            first_team = false
        end

        table.sort(teams, team_sort_by_sum)
    end

    return result
end

local function autobalance_rr(players, teams)
    local players = table.deepcopy(players)
    local teams = table.deepcopy(teams)
    local result = {}

    local team_picks = {}
    local i = 1
    for team, slots in teams do
        table.insert(team_picks, {team=team, sum=i})
        i = i + 1
    end

    while table.getsize(players) > 0 do
        for i, pick in team_picks do
            local slot = table.remove(teams[pick.team], 1)
            if not slot then continue end
            local player = table.remove(players, 1)
            if not player then break end
            pick.sum = pick.sum + i

            table.insert(result, {player=player.pos, rating=player.rating, team=pick.team, slot=slot})
        end

        table.sort(team_picks, function(a, b) return a.sum > b.sum end)
    end

    return result
end

local function autobalance_random(players, teams_arg)
    local players = table.deepcopy(players)
    local result = {}
    local teams = {}

    players = table.shuffle(players)

    for t, slots in teams_arg do
        table.insert(teams, {team=t, slots=table.deepcopy(slots)})
    end

    while table.getn(players) > 0 do
        for _, t in teams do
            local team = t['team']
            local slot = table.remove(t['slots'], 1)
            if not slot then continue end
            local player = table.remove(players, 1)

            if not player then break end

            table.insert(result, {player=player['pos'], rating=player['rating'], team=team, slot=slot})
        end
    end

    return result
end

function autobalance_quality(players)
    local teams = nil
    local quality = 0

    for _, p in players do
        local i = p['player']
        local team = p['team']
        local playerInfo = gameInfo.PlayerOptions[i]
        local player = Player.create(playerInfo.PlayerName,
                                     Rating.create(playerInfo.MEAN or 1500, playerInfo.DEV or 500))

        if not teams then
            teams = Teams.create()
        end

        teams:addPlayer(team, player)
    end

    if teams and table.getn(teams:getTeams()) > 1 then
        quality = Trueskill.computeQuality(teams)
    end

    return quality
end

--- If the game is full, GPGNetSend about it so the client can do a fancy popup if it has focus.
function PossiblyAnnounceGameFull()
    -- Search for an empty non-closed slot.
    for i = 1, numOpenSlots do
        if not gameInfo.ClosedSlots[i] then
            if not gameInfo.PlayerOptions[i] then
                return
            end
        end
    end

    -- Game is full, let's tell the client.
    GpgNetSend("GameFull")
end

local function AssignRandomStartSpots()
    local teamSpawn = gameInfo.GameOptions['TeamSpawn']

    if teamSpawn == 'fixed' then
        return
    end

    function teamsAddSpot(teams, team, spot)
        if not teams[team] then
            teams[team] = {}
        end
        table.insert(teams[team], spot)
    end

    -- rearrange players according to the provided setup
    function rearrangePlayers(data)
        gameInfo.GameOptions['Quality'] = data.quality

        -- Copy a reference to each of the PlayerData objects indexed by their original slots.
        local orgPlayerOptions = {}
        for k, p in gameInfo.PlayerOptions do
            orgPlayerOptions[k] = p
        end

        -- Rearrange the players in the slots to match the chosen configuration. The result object
        -- maps old slots to new slots, and we use orgPlayerOptions to avoid losing a reference to
        -- an object (and because swapping is too much like hard work).
        gameInfo.PlayerOptions = {}
        for _, r in data.setup do
            local playerOptions = orgPlayerOptions[r.player]
            playerOptions.Team = r.team + 1
            playerOptions.StartSpot = r.slot
            gameInfo.PlayerOptions[r.slot] = playerOptions

            -- Send team data to the server
            local playerInfo = gameInfo.PlayerOptions[r.slot]
            HostUtils.SendPlayerSettingsToServer(r.slot)
        end
    end

    local numAvailStartSpots = nil
    local scenarioInfo = nil
    if gameInfo.GameOptions.ScenarioFile and (gameInfo.GameOptions.ScenarioFile ~= "") then
        scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
    end
    if scenarioInfo then
        local armyTable = MapUtil.GetArmies(scenarioInfo)
        if armyTable then
            if gameInfo.GameOptions['RandomMap'] == 'Off' then
                numAvailStartSpots = table.getn(armyTable)
            else
                numAvailStartSpots = numberOfPlayers
            end
        end
    else
        WARN("Can't assign random start spots, no scenario selected.")
        return
    end

    local AutoTeams = gameInfo.GameOptions.AutoTeams
    local positionGroups = {}
    local teams = {}

    -- Used to actualise the virtual teams produced by the "Team -" no-team team.
    local synthesizedTeamCounter = 9
    for i = 1, numAvailStartSpots do
        if not gameInfo.ClosedSlots[i] then
            local team = nil
            local group = nil

            if AutoTeams == 'lvsr' then
                local midLine = GUI.mapView.Left() + (GUI.mapView.Width() / 2)
                local markerPos = GUI.mapView.startPositions[i].Left()

                if markerPos < midLine then
                    team = 2
                else
                    team = 3
                end
            elseif AutoTeams == 'tvsb' then
                local midLine = GUI.mapView.Top() + (GUI.mapView.Height() / 2)
                local markerPos = GUI.mapView.startPositions[i].Top()

                if markerPos < midLine then
                    team = 2
                else
                    team = 3
                end
            elseif AutoTeams == 'pvsi' then
                if math.mod(i, 2) ~= 0 then
                    team = 2
                else
                    team = 3
                end
            elseif AutoTeams == 'manual' then
                team = gameInfo.AutoTeams[i]
            else -- none
                team = gameInfo.PlayerOptions[i].Team
                group = 1
            end

            group = group or team
            if not positionGroups[group] then
                positionGroups[group] = {}
            end
            table.insert(positionGroups[group], i)

            if team ~= nil then
                -- Team 1 secretly represents "No team", so give them a real team (but one that
                -- nobody else can possibly have)
                if team == 1 then
                    team = synthesizedTeamCounter
                    synthesizedTeamCounter = synthesizedTeamCounter + 1
                end
                teamsAddSpot(teams, team, i)
            end
        end
    end
    gameInfo.GameOptions.RandomPositionGroups = positionGroups

    -- shuffle the array for randomness.
    for i, team in teams do
        teams[i] = table.shuffle(team)
    end
    teams = table.shuffle(teams)

    local ratingTable = {}
    for i = 1, numAvailStartSpots do
        local playerInfo = gameInfo.PlayerOptions[i]
        if playerInfo then
            table.insert(ratingTable, { pos=i, rating = playerInfo.MEAN - playerInfo.DEV * 3 })
        end
    end

    if teamSpawn == 'random' or teamSpawn == 'random_reveal' then
        s = autobalance_random(ratingTable, teams)
        q = autobalance_quality(s)
        rearrangePlayers{setup=s, quality=q}
        return
    end

    ratingTable = table.shuffle(ratingTable) -- random order for people with same rating
    table.sort(ratingTable, function(a, b) return a['rating'] > b['rating'] end)

    local setups = {}
    local functions = {
        rr=autobalance_rr,
        bestworst=autobalance_bestworst,
        avg=autobalance_avg,
    }

    local cmp = function(a, b) return a.quality > b.quality end
    local s, q
    for fname, f in functions do
        s = f(ratingTable, teams)
        if s then
            q = autobalance_quality(s)
            table.binsert(setups, {setup=s, quality=q}, cmp)
        end
    end

    local n_random = 0
    local frac = (teamSpawn == 'balanced_flex' or teamSpawn == 'balanced_flex_reveal') and 0.95 or 1
    -- add 100 random compositions and keep 3 with at least <frac%> of best quality
    for i=1, 100 do
        s = autobalance_random(ratingTable, teams)
        q = autobalance_quality(s)

        if q > setups[1].quality * frac then
            table.binsert(setups, {setup=s, quality=q}, cmp)
            n_random = n_random + 1
            if n_random > 2 then break end
        end
    end

    if teamSpawn == 'balanced_flex' or teamSpawn == 'balanced_flex_reveal' then
        setups = table.shuffle(setups)
    end

    best = table.remove(setups, 1)
    rearrangePlayers(best)
end


local function AssignAutoTeams()
    -- A function to take a player index and return the team they should be on.
    local getTeam
    if gameInfo.GameOptions.AutoTeams == 'lvsr' then
        local midLine = GUI.mapView.Left() + (GUI.mapView.Width() / 2)
        local startPositions = GUI.mapView.startPositions

        getTeam = function(playerIndex)
            local markerPos = startPositions[playerIndex].Left()
            if markerPos < midLine then
                return 2
            else
                return 3
            end
        end
    elseif gameInfo.GameOptions.AutoTeams == 'tvsb' then
        local midLine = GUI.mapView.Top() + (GUI.mapView.Height() / 2)
        local startPositions = GUI.mapView.startPositions

        getTeam = function(playerIndex)
            local markerPos = startPositions[playerIndex].Top()
            if markerPos < midLine then
                return 2
            else
                return 3
            end
        end
    elseif gameInfo.GameOptions.AutoTeams == 'pvsi' or gameInfo.GameOptions['RandomMap'] ~= 'Off' then
        getTeam = function(playerIndex)
            if math.mod(playerIndex, 2) ~= 0 then
                return 2
            else
                return 3
            end
        end
    elseif gameInfo.GameOptions.AutoTeams == 'manual' then
        getTeam = function(playerIndex)
            return gameInfo.AutoTeams[playerIndex] or 1
        end
    else
        return
    end

    for i = 1, LobbyComm.maxPlayerSlots do
        if not gameInfo.ClosedSlots[i] and gameInfo.PlayerOptions[i] then
            local correctTeam = getTeam(i)
            if gameInfo.PlayerOptions[i].Team ~= correctTeam then
                SetPlayerOption(i, "Team", correctTeam, true)
                SetSlotInfo(i, gameInfo.PlayerOptions[i])
            end
        end
    end
end

local function AssignAINames()
    local aiNames = import('/lua/ui/lobby/aiNames.lua').ainames
    local nameSlotsTaken = {}
    for index, faction in FactionData.Factions do
        nameSlotsTaken[index] = {}
    end
    for index, player in gameInfo.PlayerOptions do
        if not player.Human then
            local playerFaction = player.Faction
            local factionNames = aiNames[FactionData.Factions[playerFaction].Key]
            local ranNum
            repeat
                ranNum = math.random(1, table.getn(factionNames))
            until nameSlotsTaken[playerFaction][ranNum] == nil
            nameSlotsTaken[playerFaction][ranNum] = true
            player.PlayerName = factionNames[ranNum] .. " (" .. player.PlayerName .. ")"
        end
    end
end


-- call this whenever the lobby needs to exit and not go in to the game
function ReturnToMenu(reconnect)
    if lobbyComm then
        lobbyComm:Destroy()
        lobbyComm = false
    end

    local exitfn = GUI.exitBehavior

    GUI:Destroy()
    GUI = false

    if not reconnect then
        exitfn()
    else
        local ipnumber = GetCommandLineArg("/joincustom", 1)[1]
        import('/lua/ui/uimain.lua').StartJoinLobbyUI("UDP", ipnumber, localPlayerName)
    end
end

function PrintSystemMessage(id, parameters)
    AddChatText(LOCF("<LOC "..id..">Unknown system message. Check localisation file", unpack(parameters)))
end

function SendSystemMessage(id, ...)
    local data = {
        Type = "SystemMessage",
        Id = id,
        Args = arg
    }

    lobbyComm:BroadcastData(data)
    PrintSystemMessage(id, arg)
end

function SendPersonalSystemMessage(targetID, id, ...)
    if targetID ~= localPlayerID then
        local data = {
            Type = "SystemMessage",
            Id = id,
            Args = arg
        }

        lobbyComm:SendData(targetID, data)
    end
end


function PrivateChat(targetID,text)
    if targetID ~= localPlayerID then
        lobbyComm:SendData(
            targetID,
            {
                Type = 'PrivateChat',
                Text = text,
            }
        )
    end
    local targetName = FindNameForID(targetID)
    if targetName then
        GUI.chatDisplay:AppendPrivateMessage(localPlayerName, targetName, text)
    end
end

function UpdateAvailableSlots(numAvailStartSpots, scenario)
    if numAvailStartSpots > LobbyComm.maxPlayerSlots then
        WARN("Lobby requests " .. numAvailStartSpots .. " but there are only " .. LobbyComm.maxPlayerSlots .. " available")
    end

    for i = 1, numAvailStartSpots do
        local availableFactionsForSpotI = FACTION_NAMES
        if scenario.Configurations.standard.factions then
            availableFactionsForSpotI = scenario.Configurations.standard.factions[i]
        end

        local factionBmps = {}
        local factionTooltips = {}
        local factionList = {}
        for index, factionKey in availableFactionsForSpotI do
            for _, tbl in FactionData.Factions do
                if factionKey == tbl.Key then
                    factionBmps[index] = tbl.SmallIcon
                    factionTooltips[index] = tbl.TooltipID
                    factionList[index] = tbl.Key
                    break
                end
            end
        end
        if table.getn(factionBmps) > 1 then
            table.insert(factionBmps, "/faction_icon-sm/random_ico.dds")
            table.insert(factionTooltips, 'lob_random')
            table.insert(factionList, 'random')
        end

        local oldAvailableFactions = GUI.slots[i].AvailableFactions
        GUI.slots[i].AvailableFactions = factionList

        local diff = table.getn(factionList) ~= table.getn(oldAvailableFactions)
        for k = 1,table.getn(factionList) do
            if oldAvailableFactions[k] ~= factionList[k] then
                diff = true
                break
            end
        end
        if not diff then
            continue
        end

        GUI.slots[i].faction:ChangeBitmapArray(factionBmps)
        Tooltip.AddComboTooltip(GUI.slots[i].faction, factionTooltips)

        if gameInfo.PlayerOptions[i] then
            local playerFactionIndex = table.getn(factionList)
            for index,key in factionList do
                if key == oldAvailableFactions[gameInfo.PlayerOptions[i].Faction] then
                    playerFactionIndex = index
                    break
                end
            end
            if FindSlotForID(localPlayerID) == i then
                local fact = factionList[playerFactionIndex]
                for index,value in allAvailableFactionsList do
                    if fact == value then
                        GUI.factionSelector:SetSelected(index)
                        break
                    end
                end
                UpdateFactionSelector()
            else
                GUI.slots[i].faction:SetItem(playerFactionIndex)
                gameInfo.PlayerOptions[i].Faction = playerFactionIndex
            end
        end
    end

    -- if number of available slots has changed, update it
    if gameInfo.firstUpdateAvailableSlotsDone and numOpenSlots == numAvailStartSpots then
        -- Remove closed_spawn_mex if necessary
        if not gameInfo.AdaptiveMap then
            for i = 1, numAvailStartSpots do
                if gameInfo.ClosedSlots[i] and gameInfo.SpawnMex[i] then
                    ClearSlotInfo(i)
                    gameInfo.SpawnMex[i] = nil
                end
            end
        end
        return
    end

    -- reopen slots in case the new map has more startpositions then the previous map.
    if numOpenSlots < numAvailStartSpots then
        for i = numOpenSlots + 1, numAvailStartSpots do
            gameInfo.ClosedSlots[i] = nil
            gameInfo.SpawnMex[i] = nil
            GUI.slots[i]:Show()
            ClearSlotInfo(i)
            DisableSlot(i)
        end
    end
    numOpenSlots = numAvailStartSpots

    for i = 1, numAvailStartSpots do
        if gameInfo.ClosedSlots[i] then
            GUI.slots[i]:Show()
            if not gameInfo.PlayerOptions[i] then
                ClearSlotInfo(i)
            end
            if not gameInfo.PlayerOptions[i].Ready then
                EnableSlot(i)
            end
        end
    end

    for i = numAvailStartSpots + 1, LobbyComm.maxPlayerSlots do
        if lobbyComm:IsHost() and gameInfo.PlayerOptions[i] then
            local info = gameInfo.PlayerOptions[i]
            if info.Human then
                HostUtils.ConvertPlayerToObserver(i)
            else
                HostUtils.RemoveAI(i)
            end
        end
        DisableSlot(i)
        GUI.slots[i]:Hide()
        gameInfo.ClosedSlots[i] = true
        gameInfo.SpawnMex[i] = nil
    end

    gameInfo.firstUpdateAvailableSlotsDone = true
end

local function TryLaunch(skipNoObserversCheck)
    if not singlePlayer then
        local notReady = GetPlayersNotReady()
        if notReady then
            for k,v in notReady do
                AddChatText(LOCF("<LOC lobui_0203>%s isn't ready.",v))
            end
            return
        end
    end

    local teamsPresent = {}

    -- make sure there are some players (could all be observers?)
    -- Also count teams. There needs to be at least 2 teams (or all FFA) represented
    local numPlayers = 0
    local numHumanPlayers = 0
    local numTeams = 0
    for slot, player in gameInfo.PlayerOptions:pairs() do
        if player then
            numPlayers = numPlayers + 1

            if player.Human then
                numHumanPlayers = numHumanPlayers + 1
            end

            -- Make sure to increment numTeams for people in the special "-" team, represented by 1.
            if not teamsPresent[player.Team] or player.Team == 1 then
                teamsPresent[player.Team] = true
                numTeams = numTeams + 1
            end
        end
    end

    -- Ensure, for a non-sandbox game, there are some teams to fight.
    if gameInfo.GameOptions['Victory'] ~= 'sandbox' and numTeams < 2 then
        --AddChatText(LOC("<LOC lobui_0241>There must be more than one player or team or the Victory Condition must be set to Sandbox."))
        -- In case we start a game as single player we set the game temporarily to Sandbox mode. This will not change the lobby option itself!
        SPEW('GameOptions[\'Victory\'] changed temporarily from "'..gameInfo.GameOptions['Victory']..'" to "sandbox"')
        gameInfo.GameOptions['Victory'] = 'sandbox'
    end

    if numPlayers == 0 then
        AddChatText(LOC("<LOC lobui_0233>There are no players assigned to player slots, can not continue"))
        return
    end

    if not gameInfo.GameOptions.AllowObservers then
        local hostIsObserver = false
        local anyOtherObservers = false
        for k, observer in gameInfo.Observers:pairs() do
            if observer.OwnerID == localPlayerID then
                hostIsObserver = true
            else
                anyOtherObservers = true
            end
        end

        if hostIsObserver then
            AddChatText(LOC("<LOC lobui_0277>Cannot launch if the host isn't assigned a slot and observers are not allowed."))
            return
        end

        if anyOtherObservers and not skipNoObserversCheck then
            UIUtil.QuickDialog(GUI, "<LOC lobui_0278>Launching will kick observers because \"allow observers\" is disabled.  Continue?",
                                    "<LOC _Yes>", function() TryLaunch(true) end,
                                    "<LOC _No>", nil, nil, nil, true,
                                    {worldCover = false, enterButton = 1, escapeButton = 2})
            return
        end

        HostUtils.KickObservers("GameLaunched")
    end

    if not EveryoneHasEstablishedConnections(gameInfo.GameOptions.AllowObservers) then
        return
    end

    numberOfPlayers = numPlayers
    local function LaunchGame()
        -- These two things must happen before the flattening step, mostly for terrible reasons.
        -- This isn't ideal, as it leads to redundant UI repaints :/
        AssignAutoTeams()

        -- Force observers to start with the UEF skin to prevent them from launching as "random".
        if IsObserver(localPlayerID) then
            UIUtil.SetCurrentSkin("uef")
        end

        -- Eliminate the WatchedValue structures.
        gameInfo = GameInfo.Flatten(gameInfo)

        if gameInfo.GameOptions['RandomMap'] ~= 'Off' then
            autoRandMap = true
            autoMap()
        end

        SetFrontEndData('NextOpBriefing', nil)
        -- assign random factions just as game is launched
        AssignRandomFactions()
        -- fix faction indexes
        FixFactionIndexes()
        AssignRandomStartSpots()
        AssignAINames()
        local allRatings = {}
        local clanTags = {}
        for k, player in gameInfo.PlayerOptions do
            if player.Human and player.PL then
                allRatings[player.PlayerName] = player.PL
                clanTags[player.PlayerName] = player.PlayerClan
            end

            if player.OwnerID == localPlayerID then
                UIUtil.SetCurrentSkin(FACTION_NAMES[player.Faction])
            end
        end
        gameInfo.GameOptions['Ratings'] = allRatings
        gameInfo.GameOptions['ClanTags'] = clanTags

        scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)

        if scenarioInfo.AdaptiveMap then
            gameInfo.GameOptions["SpawnMex"] = gameInfo.SpawnMex
        end

        HostUtils.SendArmySettingsToServer()

        -- Tell everyone else to launch and then launch ourselves.
        -- TODO: Sending gamedata here isn't necessary unless lobbyComm is fucking stupid and allows
        -- out-of-order message delivery.
        -- Downlord: I use this in clients now to store the rehost preset. So if you're going to remove this, please
        -- check if rehosting still works for non-host players.
        lobbyComm:BroadcastData({ Type = 'Launch', GameInfo = gameInfo })

        -- set the mods
        gameInfo.GameMods = Mods.GetGameMods(gameInfo.GameMods)

        SetWindowedLobby(false)

        SavePresetToName(LAST_GAME_PRESET_NAME)

        lobbyComm:LaunchGame(gameInfo)
    end

    LaunchGame()
end

local function AlertHostMapMissing()
    if lobbyComm:IsHost() then
        HostUtils.PlayerMissingMapAlert(localPlayerID)
    else
        lobbyComm:SendData(hostID, {Type = 'MissingMap'})
    end
end

-- Refresh (with a sledgehammer) all the items in the observer list.
local function refreshObserverList()
    GUI.observerList:DeleteAllItems()

    for slot, observer in gameInfo.Observers:pairs() do
        observer.ObserverListIndex = GUI.observerList:GetItemCount() -- Pin-head William made this zero-based

        -- Create a label for this observer of the form:
        -- PlayerName (R:xxx, P:xxx, C:xxx)
        -- Such conciseness is necessary as the field in the UI is rather narrow...
        local observer_label = observer.PlayerName .. " (R:" .. observer.PL

        -- Add the ping only if this entry refers to a different client.
        if observer and (observer.OwnerID ~= localPlayerID) and observer.ObserverListIndex then
            local peer = lobbyComm:GetPeer(observer.OwnerID)

            local ping = 0
            if peer.ping ~= nil then
                ping = math.floor(peer.ping)
            end

            observer_label = observer_label .. ", P:" .. ping
        end

        -- Add the CPU score if one is available.
        local score_CPU = CPU_Benchmarks[observer.PlayerName]
        if score_CPU then
            observer_label = observer_label .. ", C:" .. score_CPU
        end
        observer_label = observer_label .. ")"

        GUI.observerList:AddItem(observer_label)
    end
end

local function UpdateGame()
    -- This allows us to assume the existence of UI elements throughout.
    if not GUI.uiCreated then
        WARN(debug.traceback(nil, "UpdateGame() pointlessly called before UI creation!"))
        return
    end

    local scenarioInfo

    if gameInfo.GameOptions.ScenarioFile and (gameInfo.GameOptions.ScenarioFile ~= "") then
        scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)

        if scenarioInfo and scenarioInfo.map and scenarioInfo.map ~= '' then
            GUI.mapView:SetScenario(scenarioInfo)
            ShowMapPositions(GUI.mapView, scenarioInfo)
            ConfigureMapListeners(GUI.mapView, scenarioInfo)
        else
            AlertHostMapMissing()
            GUI.mapView:Clear()
        end
    end

    local isHost = lobbyComm:IsHost()

    local localPlayerSlot = FindSlotForID(localPlayerID)
    if localPlayerSlot then
        local playerOptions = gameInfo.PlayerOptions[localPlayerSlot]

        -- Disable some controls if the user is ready.
        local notReady = not playerOptions.Ready

        UIUtil.setEnabled(GUI.becomeObserver, notReady)
        -- This button is enabled for all non-host players to view the configuration, and for the
        -- host to select presets (rather confusingly, one object represents both potential buttons)
        UIUtil.setEnabled(GUI.restrictedUnitsOrPresetsBtn, not isHost or notReady)

        UIUtil.setEnabled(GUI.LargeMapPreview, notReady)
        UIUtil.setEnabled(GUI.factionSelector, notReady)
        if notReady then
            UpdateFactionSelector()
        end
    else
        UIUtil.setEnabled(GUI.factionSelector, false)
    end

    gameInfo.AdaptiveMap = scenarioInfo.AdaptiveMap

    local numPlayers = GetPlayerCount()

    local numAvailStartSpots = LobbyComm.maxPlayerSlots
    if scenarioInfo then
        local armyTable = MapUtil.GetArmies(scenarioInfo)
        if armyTable then
            numAvailStartSpots = table.getn(armyTable)
        end
    end

    UpdateAvailableSlots(numAvailStartSpots, scenarioInfo)

    -- Update all slots.
    for i = 1, LobbyComm.maxPlayerSlots do
        if gameInfo.ClosedSlots[i] then
            UpdateSlotBackground(i)
        else
            if gameInfo.PlayerOptions[i] then
                SetSlotInfo(i, gameInfo.PlayerOptions[i])
            else
                ClearSlotInfo(i)
            end
        end
    end

    if not singlePlayer then
        refreshObserverList()
    end

    if isHost then
        HostUtils.RefreshButtonEnabledness()
    end
    RefreshOptionDisplayData(scenarioInfo)

    -- Update the map background to reflect the possibly-changed map.
    if Prefs.GetFromCurrentProfile('LobbyBackground') == 4 then
        RefreshLobbyBackground()
    end

    -- Set the map name at the top right corner in lobby
    if scenarioInfo.name then
        GUI.MapNameLabel:StreamText(scenarioInfo.name, 20)
    end

    -- Add Tooltip info on Map Name Label
    if scenarioInfo then
        local TTips_map_version = scenarioInfo.map_version or "1"
        local TTips_army = table.getsize(scenarioInfo.Configurations.standard.teams[1].armies)
        local TTips_sizeX = scenarioInfo.size[1] / 51.2
        local TTips_sizeY = scenarioInfo.size[2] / 51.2

        local mapTooltip = {
            text = scenarioInfo.name,
            body = '- '..LOC("<LOC lobui_0759>Map version")..' : '..TTips_map_version..'\n '..
                   '- '..LOC("<LOC lobui_0760>Max Players")..' : '..TTips_army..' max'..'\n '..
                   '- '..LOC("<LOC lobui_0761>Map Size")..' : '..TTips_sizeX..'km x '..TTips_sizeY..'km'
        }

        Tooltip.AddControlTooltip(GUI.MapNameLabel, mapTooltip)
        Tooltip.AddControlTooltip(GUI.GameQualityLabel, mapTooltip)
    end

    -- If the large map is shown, update it.
    RefreshLargeMap()

    SetRuleTitleText(gameInfo.GameOptions.GameRules or "")
    SetGameTitleText(gameInfo.GameOptions.Title or LOC("<LOC lobui_0427>FAF Game Lobby"))
    
    if not singlePlayer and isHost and GUI.autoTeams then
        GUI.autoTeams:SetState(gameInfo.GameOptions.AutoTeams,true)
        Tooltip.DestroyMouseoverDisplay()
    end
    KyrosLobby:ArrangeSlots()
end

--- Update the game quality display
function ShowGameQuality()
    KyrosLobby:UpdateTeamsSums()
    GUI.GameQualityLabel:SetText("")

    -- Can't compute a game quality for random spawns!
    if gameInfo.GameOptions.TeamSpawn ~= 'fixed' then
        return
    end

    local teams = Teams.create()

    -- Everything catches fire if the teams aren't numbered sequentially from 1.
    -- I hope it is not the case that everything catches fire when there are >2 teams, but in
    -- principle that should work...

    -- Start by creating a map from each *used* team to an element from an ascending set of integers.
    local tsTeam = 1
    local teamMap = {}
    for i = 1, LobbyComm.maxPlayerSlots do
        local playerOptions = gameInfo.PlayerOptions[i]
        -- Team 1 represents "No team", so these people are all singleton teams.
        if playerOptions and (teamMap[playerOptions.Team] == nil or playerOptions.Team == 1) then
            teamMap[playerOptions.Team] = tsTeam
            tsTeam = tsTeam + 1
        end
    end

    -- Now we just use the map to relate real teams to trueSkill teams.
    for i = 1, LobbyComm.maxPlayerSlots do
        local playerOptions = gameInfo.PlayerOptions[i]
        if playerOptions then
            -- Can't do it for AI, either, not sensibly.
            if not playerOptions.Human then
                return
            end

            local player = Player.create(
                playerOptions.PlayerName,
                Rating.create(playerOptions.MEAN, playerOptions.DEV)
            )

            teams:addPlayer(teamMap[playerOptions.Team], player)
        end
    end

    -- Nothing to do if we have only one team...
    if table.getn(teams:getTeams()) < 2 then
        return
    end

    local quality = Trueskill.computeQuality(teams)

    if quality > 0 then
        gameInfo.GameOptions.Quality = quality
        GUI.GameQualityLabel:StreamText(LOCF("<LOC lobui_0418>Game quality: %s%%", quality), 20)
    end
end

-- Holds some utility functions to do with game option management.
local OptionUtils = {
    -- Set all game options to their default values.
    SetDefaults = function()
        local options = {}
        for index, option in teamOpts do
            options[option.key] = option.values[option.default].key or option.values[option.default]
        end
        for index, option in globalOpts do
            -- Exception to make AllowObservers work because the engine requires
            -- the keys to be bool. Custom options should use 'True' or 'False'
            if option.key == 'AllowObservers' then
                options[option.key] = option.values[option.default].key
            else
                options[option.key] = option.values[option.default].key or option.values[option.default]
            end
        end

        for index, option in AIOpts do
            options[option.key] = option.values[option.default].key or option.values[option.default]
        end
        
        options.RestrictedCategories = {}
        
        SetGameOptions(options)
    end
}

-- callback when Mod Manager dialog finishes (modlist==nil on cancel)
-- FIXME: The mod manager should be given a list of game mods set by the host, which
-- clients can look at but not changed, and which don't get saved in our local prefs.
function OnModsChanged(simMods, UIMods, ignoreRefresh)
    -- We depend upon ModsManager to not allow the user to change mods they shouldn't be able to
    selectedSimMods = simMods
    selectedUIMods = UIMods

    Mods.SetSelectedMods(SetUtils.Union(selectedSimMods, selectedUIMods))
    if lobbyComm:IsHost() then
        HostUtils.UpdateMods()
    end

    if not ignoreRefresh then
        -- reload AI types in case we have enable or disable an AI mod.
        aitypes = import('/lua/ui/lobby/aitypes.lua').GetAItypes()        
        UpdateGame()
    end
end

function GetAvailableColor()
    for colorIndex, colorVal in gameColors.PlayerColors do
        if IsColorFree(colorIndex) then
            return colorIndex
        end
    end
end

--- This function is retarded.
-- Unfortunately, we're stuck with it.
-- The game requires both ArmyColor and PlayerColor be set. We don't want to have to write two fields
-- all the time, and the magic that makes PlayerData work precludes adding member functions to it.
-- So, we have this. Tough shit. :P
function SetPlayerColor(playerData, newColor)
    playerData.ArmyColor = newColor
    playerData.PlayerColor = newColor
end

function autoMap()
    local randomAutoMap
    if gameInfo.GameOptions['RandomMap'] == 'Official' then
        randomAutoMap = import('/lua/ui/dialogs/mapselect.lua').randomAutoMap(true)
    else
        randomAutoMap = import('/lua/ui/dialogs/mapselect.lua').randomAutoMap(false)
    end
end

function ClientsMissingMap()
    local ret = nil

    for index, player in gameInfo.PlayerOptions:pairs() do
        if player.BadMap then
            if not ret then ret = {} end
            table.insert(ret, player.PlayerName)
        end
    end

    for index, observer in gameInfo.Observers:pairs() do
        if observer.BadMap then
            if not ret then ret = {} end
            table.insert(ret, observer.PlayerName)
        end
    end

    return ret
end

function ClearBadMapFlags()
    for index, player in gameInfo.PlayerOptions:pairs() do
        player.BadMap = false
    end

    for index, observer in gameInfo.Observers:pairs() do
        observer.BadMap = false
    end
end

function EnableSlot(slot)
    GUI.slots[slot].team:Enable()
    GUI.slots[slot].color:Enable()
    GUI.slots[slot].faction:Enable()
    GUI.slots[slot].ready:Enable()
end

function DisableSlot(slot, exceptReady)
    GUI.slots[slot].team:Disable()
    GUI.slots[slot].color:Disable()
    GUI.slots[slot].faction:Disable()
    if not exceptReady then
        GUI.slots[slot].ready:Disable()
    end
end

-- set up player "slots" which is the line representing a player and player specific options
function CreateSlotsUI(makeLabel)
    KyrosLobby:CreateSlotsUI()
end

-- create UI won't typically be called directly by another module
function CreateUI(maxPlayers)
    local Checkbox = import('/lua/maui/checkbox.lua').Checkbox
    local Text = import('/lua/maui/text.lua').Text
    local ResourceMapPreview = import('/lua/ui/controls/resmappreview.lua').ResourceMapPreview
    local MapPreview = import('/lua/ui/controls/mappreview.lua').MapPreview
    local MultiLineText = import('/lua/maui/multilinetext.lua').MultiLineText
    local EffectHelpers = import('/lua/maui/effecthelpers.lua')
    local ItemList = import('/lua/maui/itemlist.lua').ItemList
    local Prefs = import('/lua/user/prefs.lua')
    local Tooltip = import('/lua/ui/game/tooltip.lua')

    local isHost = lobbyComm:IsHost()
    local lastFaction = GetSanitisedLastFaction()
    UIUtil.SetCurrentSkin(FACTION_NAMES[lastFaction])

    ---------------------------------------------------------------------------
    -- Set up main control panels
    ---------------------------------------------------------------------------
    GUI.panel = Bitmap(GUI, UIUtil.SkinnableFile("/scx_menu/lan-game-lobby/lobby.dds"))
    LayoutHelpers.AtCenterIn(GUI.panel, GUI)
    GUI.panelWideLeft = Bitmap(GUI, UIUtil.SkinnableFile('/scx_menu/lan-game-lobby/wide.dds'))
    LayoutHelpers.CenteredLeftOf(GUI.panelWideLeft, GUI.panel)
    GUI.panelWideLeft.Left:Set(function() return GUI.Left() end)
    GUI.panelWideRight = Bitmap(GUI, UIUtil.SkinnableFile('/scx_menu/lan-game-lobby/wide.dds'))
    LayoutHelpers.CenteredRightOf(GUI.panelWideRight, GUI.panel)
    GUI.panelWideRight.Right:Set(function() return GUI.Right() end)

    -- Create a label with a given size and initial text
    local function makeLabel(text, size)
        return UIUtil.CreateText(GUI.panel, text, size, 'Arial Gras', true)
    end

    -- Map name label
    GUI.MapNameLabel = makeLabel(LOC("<LOC LOADING>Loading..."), 17)
    LayoutHelpers.AtRightTopIn(GUI.MapNameLabel, GUI.panel, 5, 45)

    -- Game Quality Label
    GUI.GameQualityLabel = makeLabel("", 11)
    LayoutHelpers.AtRightTopIn(GUI.GameQualityLabel, GUI.panel, 5, 64)

    -- Title Label
    GUI.titleText = makeLabel(LOC("<LOC lobui_0427>FAF Game Lobby"), 17)
    LayoutHelpers.AtLeftTopIn(GUI.titleText, GUI.panel, 5, 20)

    if isHost then
        GUI.titleText.HandleEvent = function(self, event)
            if event.Type == 'ButtonPress' then
                ShowTitleDialog()
            end
        end
    end

    -- Rule Label
    local RuleLabel = TextArea(GUI.panel, 350, 34)
    GUI.RuleLabel = RuleLabel
    RuleLabel:SetFont('Arial Gras', 11)
    RuleLabel:SetColors("B9BFB9", "00000000", "B9BFB9", "00000000")
    LayoutHelpers.AtLeftTopIn(RuleLabel, GUI.panel, 5, 44)
    RuleLabel:DeleteAllItems()
    local tmptext
    if isHost then
        tmptext = LOC("<LOC lobui_0420>No Rules: Click to add rules")
        RuleLabel:SetColors("FFCC00")
    else
        tmptext = LOC("<LOC lobui_0421>No rules")
    end

    RuleLabel:SetText(tmptext)
    if isHost then
        RuleLabel.OnClick = function(self)
            ShowRuleDialog()
        end
    end

    -- Mod Label
    GUI.ModFeaturedLabel = makeLabel("", 13)
    LayoutHelpers.AtLeftTopIn(GUI.ModFeaturedLabel, GUI.panel, 50, 61)

    -- Set the mod name to a value appropriate for the mod in use.
    local modLabels = {
        ["init_faf.lua"] = "FA Forever",
        ["init_blackops.lua"] = "BlackOps",
        ["init_coop.lua"] = "COOP",
        ["init_balancetesting.lua"] = "Balance Testing",
        ["init_gw.lua"] = "Galactic War",
        ["init_labwars.lua"] = "Labwars",
        ["init_ladder1v1.lua"] = "Ladder 1v1",
        ["init_nomads.lua"] = "Nomads Mod",
        ["init_phantomx.lua"] = "PhantomX",
        ["init_supremedestruction.lua"] = "SupremeDestruction",
        ["init_xtremewars.lua"] = "XtremeWars",

    }
    GUI.ModFeaturedLabel:StreamText(modLabels[argv.initName] or "", 20)

    -- Lobby options panel
    GUI.LobbyOptions = UIUtil.CreateButtonWithDropshadow(GUI.panel, '/BUTTON/medium/', LOC("<LOC tooltipui0705>Settings"))
    LayoutHelpers.AtRightTopIn(GUI.LobbyOptions, GUI.panel, 44, 3)
    GUI.LobbyOptions.OnClick = function()
        ShowLobbyOptionsDialog()
    end
    Tooltip.AddButtonTooltip(GUI.LobbyOptions, 'lobby_click_Settings')

    -- Logo
    GUI.logo = Bitmap(GUI, '/textures/ui/common/scx_menu/lan-game-lobby/logo.dds')
    LayoutHelpers.AtLeftTopIn(GUI.logo, GUI, 1, 1)

    -- Version texts
    local bool ShowPatch = false
    GUI.gameVersionText = UIUtil.CreateText(GUI.panel, "Game Patch " .. GameVersion(), 9, UIUtil.bodyFont)
    GUI.gameVersionText:SetColor('677983')
    GUI.gameVersionText:SetDropShadow(true)
    LayoutHelpers.AtLeftTopIn(GUI.gameVersionText, GUI.panel, 70, 3)
    GUI.gameVersionText.HandleEvent = function (self, event)
        if event.Type == 'MouseEnter' then
            self:SetColor('ffffff')
        elseif event.Type == 'MouseExit' then
            self:SetColor('677983')
        elseif event.Type == 'ButtonPress' then
            Changelog.CreateUI(GUI, true)
        end
    end

    -- Player Slots
    GUI.playerPanel = Group(GUI.panel, "playerPanel")
    LayoutHelpers.AtLeftTopIn(GUI.playerPanel, GUI.panel, 6, 70)
    GUI.playerPanel.Width:Set(706)
    GUI.playerPanel.Bottom:Set(377)

    -- Observer section
    GUI.observerPanel = Group(GUI.panel, "observerPanel")
    UIUtil.SurroundWithBorder(GUI.observerPanel, '/scx_menu/lan-game-lobby/frame/')

    -- Scale the observer panel according to the buttons we are showing.
    local obsOffset
    local obsHeight
    if isHost then
        obsHeight = 159
        obsOffset = 545
    else
        obsHeight = 206
        obsOffset = 503
    end
    LayoutHelpers.AtLeftTopIn(GUI.observerPanel, GUI.panel, 512, obsOffset)
    GUI.observerPanel.Width:Set(278)
    GUI.observerPanel.Height:Set(obsHeight)

    -- Chat
    GUI.chatDisplay = ChatBox(GUI.panel, {Padding = {3,3,3,3}})
    GUI.chatDisplay.Left:Set(function() return GUI.panel.Left() + 11 end)
    GUI.chatDisplay.Width:Set(478)
    GUI.chatDisplay.Top:Set(function() return GUI.playerPanel.Bottom() + 20 end)
    GUI.chatDisplay.Bottom:Set(function() return GUI.panel.Top() + 704 end)
    UIUtil.SurroundWithBorder(GUI.chatDisplay, '/scx_menu/lan-game-lobby/frame/')
    GUI.chatEdit = GUI.chatDisplay.ChatEdit
    GUI.chatPanel = GUI.panel

    -- Map Preview
    GUI.mapPanel = Group(GUI.panel, "mapPanel")
    UIUtil.SurroundWithBorder(GUI.mapPanel, '/scx_menu/lan-game-lobby/frame/')
    LayoutHelpers.AtLeftTopIn(GUI.mapPanel, GUI.panel, 813, 88)
    GUI.mapPanel.Width:Set(198)
    GUI.mapPanel.Height:Set(198)
    LayoutHelpers.DepthOverParent(GUI.mapPanel, GUI.panel, 2)

    -- Map Preview Info Labels
    local tooltipText = {}
    tooltipText['text'] = LOC("<LOC lobui_0772>Map Preview")
    -- Map Preview Info Labels
    if isHost then
        tooltipText['body'] = LOCF("%s\n%s", "<LOC lobui_0769>Left click ACU icon to move yourself or swap players.", "<LOC lobui_0770>Right click ACU icon to close or open the slot.")
    else
        tooltipText['body'] = LOC("<LOC lobui_0771>Left click ACU icon to move yourself.")
    end
    Tooltip.AddControlTooltip(GUI.mapPanel, tooltipText, 0,198)
    
    GUI.optionsPanel = Group(GUI.panel, "optionsPanel") -- ORANGE Square in Screenshoot
    UIUtil.SurroundWithBorder(GUI.optionsPanel, '/scx_menu/lan-game-lobby/frame/')
    LayoutHelpers.AtLeftTopIn(GUI.optionsPanel, GUI.panel, 813, 325)
    GUI.optionsPanel.Width:Set(198)
    GUI.optionsPanel.Height:Set(337)
    LayoutHelpers.DepthOverParent(GUI.optionsPanel, GUI.panel, 2)

    ---------------------------------------------------------------------------
    -- set up map panel
    ---------------------------------------------------------------------------
    GUI.mapView = ResourceMapPreview(GUI.mapPanel, 200, 3, 5)
    LayoutHelpers.AtLeftTopIn(GUI.mapView, GUI.mapPanel, -1, -1)
    LayoutHelpers.DepthOverParent(GUI.mapView, GUI.mapPanel, -1)

    GUI.LargeMapPreview = UIUtil.CreateButtonWithDropshadow(GUI.mapPanel, '/BUTTON/zoom/', "")
    LayoutHelpers.AtRightIn(GUI.LargeMapPreview, GUI.mapPanel, -1)
    LayoutHelpers.AtBottomIn(GUI.LargeMapPreview, GUI.mapPanel, -1)
    LayoutHelpers.DepthOverParent(GUI.LargeMapPreview, GUI.mapPanel, 2)
    Tooltip.AddButtonTooltip(GUI.LargeMapPreview, 'lob_click_LargeMapPreview')
    GUI.LargeMapPreview.OnClick = function()
        CreateBigPreview(GUI)
    end

    -- Checkbox Show changed Options
    local cbox_ShowChangedOption = UIUtil.CreateCheckbox(GUI.optionsPanel, '/CHECKBOX/', LOC("<LOC lobui_0422>Hide default options"), true, 11)
    LayoutHelpers.AtLeftTopIn(cbox_ShowChangedOption, GUI.optionsPanel, 35, -32)

    Tooltip.AddCheckboxTooltip(cbox_ShowChangedOption, {text=LOC("<LOC lobui_0422>Hide default options"), body=LOC("<LOC lobui_0423>Show only changed Options and Advanced Map Options")})
    cbox_ShowChangedOption.OnCheck = function(self, checked)
        HideDefaultOptions = checked
        RefreshOptionDisplayData()
        GUI.OptionContainer.ScrollSetTop(GUI.OptionContainer, 'Vert', 0)
        Prefs.SetToCurrentProfile('LobbyHideDefaultOptions', tostring(checked))
    end

    -- A buton that, for the host, is "game options", but for everyone else shows a ready-only mod
    -- manager.
    if isHost then
        GUI.gameoptionsButton = UIUtil.CreateButtonWithDropshadow(GUI.optionsPanel, '/BUTTON/medium/', "<LOC _Options>")
        Tooltip.AddButtonTooltip(GUI.gameoptionsButton, 'lob_select_map')
        GUI.gameoptionsButton.OnClick = function(self)
            local mapSelectDialog

            autoRandMap = false
            local function selectBehavior(selectedScenario, changedOptions, restrictedCategories)
                local options = {}
                if autoRandMap then
                    options['ScenarioFile'] = selectedScenario.file
                else
                    mapSelectDialog:Destroy()
                    GUI.chatEdit:AcquireFocus()

                    -- remove old 'Advanced options incase of new map
                    if gameInfo.GameOptions.ScenarioFile and string.lower(selectedScenario.file) ~= string.lower(gameInfo.GameOptions.ScenarioFile) then
                        local scenario = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
                        if scenario.options then
                            for _,value in scenario.options do
                                gameInfo.GameOptions[value.key] = nil
                            end
                        end
                    end

                    for optionKey, data in changedOptions do
                        options[optionKey] = data.value
                    end
                    options['ScenarioFile'] = selectedScenario.file
                    options['RestrictedCategories'] = restrictedCategories

                    -- every new map, clear the flags, and clients will report if a new map is bad
                    ClearBadMapFlags()
                    HostUtils.UpdateMods()
                    SetGameOptions(options)
                end
                for optionKey, data in changedOptions do
                    if optionKey == 'AutoTeams' then
                        AssignAutoTeams()
                    end
                end
            end

            local function exitBehavior()
                mapSelectDialog:Close()
                GUI.chatEdit:AcquireFocus()
                UpdateGame()
            end

            GUI.chatEdit:AbandonFocus()

            mapSelectDialog = import('/lua/ui/dialogs/mapselect.lua').CreateDialog(
                selectBehavior,
                exitBehavior,
                GUI,
                singlePlayer,
                gameInfo.GameOptions.ScenarioFile,
                gameInfo.GameOptions,
                availableMods,
                OnModsChanged
            )
        end
    else
        local modsManagerCallback = function(active_sim_mods, active_ui_mods)
            import('/lua/mods.lua').SetSelectedMods(SetUtils.Union(active_sim_mods, active_ui_mods))
            RefreshOptionDisplayData()
        end
        GUI.gameoptionsButton = UIUtil.CreateButtonWithDropshadow(GUI.optionsPanel, '/BUTTON/medium/', LOC("<LOC _Mod_Manager>"))
        GUI.gameoptionsButton.OnClick = function(self, modifiers)
            import('/lua/ui/lobby/ModsManager.lua').CreateDialog(GUI, false, nil, modsManagerCallback)
        end
        Tooltip.AddButtonTooltip(GUI.gameoptionsButton, 'Lobby_Mods')
    end

    LayoutHelpers.AtBottomIn(GUI.gameoptionsButton, GUI.optionsPanel, -51)
    LayoutHelpers.AtHorizontalCenterIn(GUI.gameoptionsButton, GUI.optionsPanel, 1)

    ---------------------------------------------------------------------------
    -- set up chat display
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    -- Option display
    ---------------------------------------------------------------------------
    GUI.OptionContainer = Group(GUI.optionsPanel)
    GUI.OptionContainer.Bottom:Set(function() return GUI.optionsPanel.Bottom() end)

    -- Leave space for the scrollbar.
    GUI.OptionContainer.Width:Set(function() return GUI.optionsPanel.Width() - 18 end)
    GUI.OptionContainer.top = 0
    LayoutHelpers.AtLeftTopIn(GUI.OptionContainer, GUI.optionsPanel, 1, 1)
    LayoutHelpers.DepthOverParent(GUI.OptionContainer, GUI.optionsPanel, -1)

    GUI.OptionDisplay = {}

    function CreateOptionElements()
        local function CreateElement(index)
            local element = Group(GUI.OptionContainer)

            element.bg = Bitmap(element)
            element.bg:SetSolidColor('ff333333')
            element.bg.Left:Set(element.Left)
            element.bg.Right:Set(element.Right)
            element.bg.Bottom:Set(function() return element.value.Bottom() + 2 end)
            element.bg.Top:Set(element.Top)

            element.bg2 = Bitmap(element)
            element.bg2:SetSolidColor('ff000000')
            element.bg2.Left:Set(function() return element.bg.Left() + 1 end)
            element.bg2.Right:Set(function() return element.bg.Right() - 1 end)
            element.bg2.Bottom:Set(function() return element.bg.Bottom() - 1 end)
            element.bg2.Top:Set(function() return element.value.Top() + 0 end)

            element.Height:Set(36)
            element.Width:Set(GUI.OptionContainer.Width)
            element:DisableHitTest()

            element.text = UIUtil.CreateText(element, '', 14, "Arial")
            element.text:SetColor(UIUtil.fontColor)
            element.text:DisableHitTest()
            LayoutHelpers.AtLeftTopIn(element.text, element, 5)

            element.value = UIUtil.CreateText(element, '', 14, "Arial")
            element.value:SetColor(UIUtil.fontOverColor)
            element.value:DisableHitTest()
            LayoutHelpers.AtRightTopIn(element.value, element, 5, 16)

            GUI.OptionDisplay[index] = element
        end

        CreateElement(1)
        LayoutHelpers.AtLeftTopIn(GUI.OptionDisplay[1], GUI.OptionContainer)

        local index = 2
        while index ~= 10 do
            CreateElement(index)
            LayoutHelpers.Below(GUI.OptionDisplay[index], GUI.OptionDisplay[index-1])
            index = index + 1
        end
    end
    CreateOptionElements()

    local numLines = function() return table.getsize(GUI.OptionDisplay) end

    local function DataSize()
        if HideDefaultOptions then
            return table.getn(nonDefaultFormattedOptions)
        else
            return table.getn(formattedOptions)
        end
    end

    -- called when the scrollbar for the control requires data to size itself
    -- GetScrollValues must return 4 values in this order:
    -- rangeMin, rangeMax, visibleMin, visibleMax
    -- aixs can be "Vert" or "Horz"
    GUI.OptionContainer.GetScrollValues = function(self, axis)
        local size = DataSize()
        --LOG(size, ":", self.top, ":", math.min(self.top + numLines, size))
        return 0, size, self.top, math.min(self.top + numLines(), size)
    end

    -- called when the scrollbar wants to scroll a specific number of lines (negative indicates scroll up)
    GUI.OptionContainer.ScrollLines = function(self, axis, delta)
        self:ScrollSetTop(axis, self.top + math.floor(delta))
    end

    -- called when the scrollbar wants to scroll a specific number of pages (negative indicates scroll up)
    GUI.OptionContainer.ScrollPages = function(self, axis, delta)
        self:ScrollSetTop(axis, self.top + math.floor(delta) * numLines())
    end

    -- called when the scrollbar wants to set a new visible top line
    GUI.OptionContainer.ScrollSetTop = function(self, axis, top)
        top = math.floor(top)
        if top == self.top then return end
        local size = DataSize()
        self.top = math.max(math.min(size - numLines() , top), 0)
        self:CalcVisible()
    end

    -- called to determine if the control is scrollable on a particular access. Must return true or false.
    GUI.OptionContainer.IsScrollable = function(self, axis)
        return true
    end
    -- determines what controls should be visible or not
    GUI.OptionContainer.CalcVisible = function(self)
        local function SetTextLine(line, data, lineID)
            if data.mod then
                -- The special label at the top stating the number of mods.
                line.text:SetColor('ffff7777')
                LayoutHelpers.AtHorizontalCenterIn(line.text, line, 5)
                LayoutHelpers.AtHorizontalCenterIn(line.value, line, 5, 16)
                LayoutHelpers.ResetRight(line.value)
            else
                -- Game options.
                line.text:SetColor(UIUtil.fontColor)
                LayoutHelpers.AtLeftTopIn(line.text, line, 5)
                LayoutHelpers.AtRightTopIn(line.value, line, 5, 16)
                LayoutHelpers.ResetLeft(line.value)
            end
            line.text:SetText(LOCF(data.text, data.key))
            line.bg:Show()
            line.value:SetText(LOCF(data.value, data.key))
            line.bg2:Show()
            line.bg.HandleEvent = Group.HandleEvent
            line.bg2.HandleEvent = Bitmap.HandleEvent
            if data.tooltip then
                Tooltip.AddControlTooltip(line.bg, data.tooltip)
                Tooltip.AddControlTooltip(line.bg2, data.valueTooltip)
            end
        end

        local optionsToUse
        if HideDefaultOptions then
            optionsToUse = nonDefaultFormattedOptions
        else
            optionsToUse = formattedOptions
        end

        for i, v in GUI.OptionDisplay do
            if optionsToUse[i + self.top] then
                SetTextLine(v, optionsToUse[i + self.top], i + self.top)
            else
                v.text:SetText('')
                v.value:SetText('')
                v.bg:Hide()
                v.bg2:Hide()
            end
        end
    end

    GUI.OptionContainer.HandleEvent = function(self, event)
        if event.Type == 'WheelRotation' then
            local lines = 1
            if event.WheelRotation > 0 then
                lines = -1
            end
            self:ScrollLines(nil, lines)
        end
    end

    RefreshOptionDisplayData()

    GUI.OptionContainerScroll = UIUtil.CreateLobbyVertScrollbar(GUI.OptionContainer, 2) 
    LayoutHelpers.DepthOverParent(GUI.OptionContainerScroll, GUI.OptionContainer, 2)

    -- Launch Button
    local launchGameButton = UIUtil.CreateButtonWithDropshadow(GUI.chatPanel, '/BUTTON/large/', LOC("<LOC tooltipui0173>Launch Game"))
    GUI.launchGameButton = launchGameButton
    LayoutHelpers.AtHorizontalCenterIn(launchGameButton, GUI)
    LayoutHelpers.AtBottomIn(launchGameButton, GUI.panel, -8)
    Tooltip.AddButtonTooltip(launchGameButton, 'Lobby_Launch')
    UIUtil.setVisible(launchGameButton, isHost)
    launchGameButton.OnClick = function(self)
        TryLaunch(false)
    end

    -- Create skirmish mode's "load game" button.
    local loadButton = UIUtil.CreateButtonWithDropshadow(GUI.optionsPanel, '/BUTTON/medium/',"<LOC lobui_0176>Load")
    GUI.loadButton = loadButton
    UIUtil.setVisible(loadButton, singlePlayer)
    LayoutHelpers.AtHorizontalCenterIn(loadButton, GUI.gameoptionsButton)
    LayoutHelpers.Below(loadButton, GUI.gameoptionsButton, 9)
    loadButton.OnClick = function(self, modifiers)
        import('/lua/ui/dialogs/saveload.lua').CreateLoadDialog(GUI)
    end
    Tooltip.AddButtonTooltip(loadButton, 'Lobby_Load')

    -- Create the "Lobby presets" button for the host. If not the host, the same field is occupied
    -- instead by the read-only "Unit Manager" button.
    GUI.restrictedUnitsOrPresetsBtn = UIUtil.CreateButtonWithDropshadow(GUI.optionsPanel, '/BUTTON/medium/', "")

    if singlePlayer then
        GUI.restrictedUnitsOrPresetsBtn:Hide()
    elseif isHost then
        GUI.restrictedUnitsOrPresetsBtn.label:SetText(LOC("<LOC lobui_0424>Presets"))
        GUI.restrictedUnitsOrPresetsBtn.OnClick = function(self, modifiers)
            ShowPresetDialog()
        end
        Tooltip.AddButtonTooltip(GUI.restrictedUnitsOrPresetsBtn, 'Lobby_presetDescription')
    else
        GUI.restrictedUnitsOrPresetsBtn.label:SetText(LOC("<LOC lobui_0332>Unit Manager"))
        GUI.restrictedUnitsOrPresetsBtn.OnClick = function(self, modifiers)
            import('/lua/ui/lobby/UnitsManager.lua').CreateDialog(GUI.panel, gameInfo.GameOptions.RestrictedCategories, function() end, function() end, false)
        end
        Tooltip.AddButtonTooltip(GUI.restrictedUnitsOrPresetsBtn, 'lob_RestrictedUnitsClient')
    end
    LayoutHelpers.AtHorizontalCenterIn(GUI.restrictedUnitsOrPresetsBtn, GUI.gameoptionsButton)
    LayoutHelpers.Below(GUI.restrictedUnitsOrPresetsBtn, GUI.gameoptionsButton, 9)

    ---------------------------------------------------------------------------
    -- Checkbox Show changed Options
    ---------------------------------------------------------------------------
    cbox_ShowChangedOption:SetCheck(HideDefaultOptions, false)

    ---------------------------------------------------------------------------
    -- set up : player grid
    ---------------------------------------------------------------------------

    -- For disgusting reasons, we pass the label factory as a parameter.
    CreateSlotsUI(makeLabel)

    -- Exit Button
    GUI.exitButton = UIUtil.CreateButtonWithDropshadow(GUI.chatPanel, '/BUTTON/medium/', LOC("<LOC tooltipui0285>Exit"))
    LayoutHelpers.AtLeftIn(GUI.exitButton, GUI.chatDisplay, 33)
    LayoutHelpers.AtVerticalCenterIn(GUI.exitButton, launchGameButton, 7)
    if HasCommandLineArg("/gpgnet") then
        -- Quit to desktop
        GUI.exitButton.label:SetText(LOC("<LOC _Exit>"))
        Tooltip.AddButtonTooltip(GUI.exitButton, 'esc_exit')
    else
        -- Back to main menu
        GUI.exitButton.label:SetText(LOC("<LOC _Back>"))
        Tooltip.AddButtonTooltip(GUI.exitButton, 'esc_quit')
    end

    GUI.exitButton.OnClick = GUI.exitLobbyEscapeHandler


    -- Small buttons are 100 wide, 44 tall

    -- Default option button
    GUI.defaultOptions = UIUtil.CreateButtonStd(GUI.observerPanel, '/BUTTON/defaultoption/')
    -- If we're the host, position the buttons lower down (and eventually shrink the observer panel)
    if not isHost then
        GUI.defaultOptions:Hide()
    end
    LayoutHelpers.AtLeftTopIn(GUI.defaultOptions, GUI.observerPanel, 11, -94)

    Tooltip.AddButtonTooltip(GUI.defaultOptions, 'lob_click_rankedoptions')
    if not isHost then
        GUI.defaultOptions:Disable()
    else
        GUI.defaultOptions.OnClick = function()
            -- Return all options to their default values.
            OptionUtils.SetDefaults()
            lobbyComm:BroadcastData({ Type = "SetAllPlayerNotReady" })
            UpdateGame()
        end
    end

    -- RANDOM MAP BUTTON --
    GUI.randMap = UIUtil.CreateButtonStd(GUI.observerPanel, '/BUTTON/randommap/')
    LayoutHelpers.RightOf(GUI.randMap, GUI.defaultOptions, -19)
    Tooltip.AddButtonTooltip(GUI.randMap, 'lob_click_randmap')
    if not isHost then
        GUI.randMap:Hide()
    else
        GUI.randMap.OnClick = function()
            local randomMap
            local mapSelectDialog

            autoRandMap = false

            -- Load the set of all available maps, with a slight evil hack on the mapselect module.
            local mapDialog = import('/lua/ui/dialogs/mapselect.lua')
            local allMaps = mapDialog.LoadScenarios()  -- Result will be cached.

            -- Only include maps which have enough slots for the players we have.
            local filteredMaps = table.filter(allMaps,
                function(scenInfo)
                    local supportedPlayers = table.getsize(scenInfo.Configurations.standard.teams[1].armies)
                    return supportedPlayers >= GetPlayerCount()
                end
            )
            local mapCount = table.getn(filteredMaps)
            local selectedMap = filteredMaps[math.floor(math.random(1, mapCount))]

            -- Set the new map.
            SetGameOption('ScenarioFile', selectedMap.file)
            ClearBadMapFlags()
            UpdateGame()
        end
    end

    local autoteamButtonStates = {
        {
            key = 'tvsb',
            tooltip = 'lob_auto_tvsb'
        },
        {
            key = 'lvsr',
            tooltip = 'lob_auto_lvsr'
        },
        {
            key = 'pvsi',
            tooltip = 'lob_auto_pvsi'
        },
        {
            key = 'manual',
            tooltip = 'lob_auto_manual'
        },
        {
            key = 'none',
            tooltip = 'lob_auto_none'
        },
    }

    local initialState = Prefs.GetFromCurrentProfile("LobbyOpt_AutoTeams") or "none"
    GUI.autoTeams = ToggleButton(GUI.observerPanel, '/BUTTON/autoteam/', autoteamButtonStates, initialState)

    LayoutHelpers.RightOf(GUI.autoTeams, GUI.randMap, -19)
    if not isHost then
        GUI.autoTeams:Hide()
    else
        GUI.autoTeams.OnStateChanged = function(self, newState)
            SetGameOption('AutoTeams', newState)
            AssignAutoTeams()
        end
    end
    
    -- CLOSE/OPEN EMPTY SLOTS BUTTON --
    GUI.closeEmptySlots = UIUtil.CreateButtonStd(GUI.observerPanel, '/BUTTON/closeslots/')
    LayoutHelpers.AtLeftTopIn(GUI.closeEmptySlots, GUI.defaultOptions, 0, 47)
    Tooltip.AddButtonTooltip(GUI.closeEmptySlots, 'lob_close_empty_slots')
    if not isHost then
        GUI.closeEmptySlots:Hide()
        LayoutHelpers.AtLeftTopIn(GUI.closeEmptySlots, GUI.defaultOptions, -40, 47)
    else
        GUI.closeEmptySlots.OnClick = function(self, modifiers)
            if lobbyComm:IsHost() then
                if modifiers.Ctrl then
                    for slot = 1,numOpenSlots do
                        HostUtils.SetSlotClosed(slot, false)
                    end
                    return
                end
                local openSpot = false
                for slot = 1,numOpenSlots do
                    openSpot = openSpot or not (gameInfo.PlayerOptions[slot] or gameInfo.ClosedSlots[slot])
                end
                if modifiers.Right and gameInfo.AdaptiveMap then
                    for slot = 1,numOpenSlots do
                        if openSpot then
                            if not (gameInfo.PlayerOptions[slot] or gameInfo.ClosedSlots[slot]) then
                                HostUtils.SetSlotClosedSpawnMex(slot)
                            end
                        else
                            if gameInfo.ClosedSlots[slot] and gameInfo.SpawnMex[slot] then
                                HostUtils.SetSlotClosed(slot, false)
                            end
                        end
                    end
                else
                    for slot = 1,numOpenSlots do
                        if not gameInfo.SpawnMex[slot] then
                            HostUtils.SetSlotClosed(slot, openSpot)
                        end
                    end
                end
            end
        end
    end
    

    -- GO OBSERVER BUTTON --
    GUI.becomeObserver = UIUtil.CreateButtonStd(GUI.observerPanel, '/BUTTON/observer/')
    LayoutHelpers.RightOf(GUI.becomeObserver, GUI.closeEmptySlots, -19)
    Tooltip.AddButtonTooltip(GUI.becomeObserver, 'lob_become_observer')
    GUI.becomeObserver.OnClick = function()
        if IsPlayer(localPlayerID) then
            if isHost then
                HostUtils.ConvertPlayerToObserver(FindSlotForID(localPlayerID))
            else
                lobbyComm:SendData(hostID, {Type = 'RequestConvertToObserver'})
            end
        elseif IsObserver(localPlayerID) then
            if isHost then
                HostUtils.ConvertObserverToPlayer(FindObserverSlotForID(localPlayerID))
            else
                lobbyComm:SendData(hostID, {Type = 'RequestConvertToPlayer'})
            end
        end
    end

    -- CPU BENCH BUTTON --
    GUI.rerunBenchmark = UIUtil.CreateButtonStd(GUI.observerPanel, '/BUTTON/cputest/', '', 11)
    LayoutHelpers.RightOf(GUI.rerunBenchmark, GUI.becomeObserver, -19)
    Tooltip.AddButtonTooltip(GUI.rerunBenchmark,{text=LOC("<LOC lobui_0425>Run CPU Benchmark Test"), body=LOC("<LOC lobui_0426>Recalculates your CPU rating.")})

    -- Observer List
    GUI.observerList = ItemList(GUI.observerPanel)
    GUI.observerList:SetFont(UIUtil.bodyFont, 12)
    GUI.observerList:SetColors(UIUtil.fontColor, "00000000", UIUtil.fontOverColor, UIUtil.highlightColor, "ffbcfffe")
    GUI.observerList.Left:Set(function() return GUI.observerPanel.Left() + 4 end)
    GUI.observerList.Bottom:Set(function() return GUI.observerPanel.Bottom() end)
    GUI.observerList.Top:Set(function() return GUI.observerPanel.Top() + 2 end)
    GUI.observerList.Right:Set(function() return GUI.observerPanel.Right() - 15 end)
    GUI.observerList.OnClick = function(self, row, event)
        if isHost and event.Modifiers.Right then
            UIUtil.QuickDialog(GUI, "<LOC lobui_0166>Are you sure?",
                                    "<LOC lobui_0167>Kick Player", function()
                                        SendSystemMessage("lobui_0756", gameInfo.Observers[row+1].PlayerName)
                                        lobbyComm:EjectPeer(gameInfo.Observers[row+1].OwnerID, "KickedByHost")
                                    end,
                                    "<LOC _Cancel>", nil,
                                    nil, nil,
                                    true,
                                    {worldCover = false, enterButton = 1, escapeButton = 2}
            )
        end
    end
    UIUtil.CreateLobbyVertScrollbar(GUI.observerList, 0, 0, -1)

    -- Setup large pretty faction selector and set the factional background to its initial value.
    local lastFaction = GetSanitisedLastFaction()
    CreateUI_Faction_Selector(lastFaction)

    RefreshLobbyBackground(lastFaction)

    GUI.uiCreated = true

    if singlePlayer then
        -- observers are always allowed in skirmish games.
        SetGameOption("AllowObservers", true)
        -- Hide all the multiplayer-only UI elements (we still create them because then we get to
        -- mostly forget that we're in single-player mode everywhere else (stuff silently becomes a
        -- nop, instead of needing to keep checking if UI controls actually exist...

        GUI.closeEmptySlots:Hide()
        GUI.becomeObserver:Hide()
        GUI.autoTeams:Hide()
        GUI.defaultOptions:Hide()
        GUI.rerunBenchmark:Hide()
        GUI.randMap:Hide()
        GUI.observerPanel:Hide()
    end

    ---------------------------------------------------------------------------
    -- other logic, including lobby callbacks
    ---------------------------------------------------------------------------
    GUI.posGroup = false
    -- get ping times
    GUI.pingThread = ForkThread(
    function()
        while lobbyComm do
            for slot, player in gameInfo.PlayerOptions:pairs() do
                if player.Human and player.OwnerID ~= localPlayerID then
                    local peer = lobbyComm:GetPeer(player.OwnerID)
                    local ping = peer.ping
                    local connectionStatus = CalcConnectionStatus(peer)
                    GUI.slots[slot].pingStatus.ConnectionStatus = connectionStatus
                    if ping then
                        ping = math.floor(ping)
                        GUI.slots[slot].pingStatus.PingActualValue = ping
                        GUI.slots[slot].pingStatus:SetValue(ping)
                        if ping > 500 then
                            GUI.slots[slot].pingStatus:Show()
                        else
                            GUI.slots[slot].pingStatus:Hide()
                        end
                        -- Set the ping bar to a colour representing the status of our connection.
                        GUI.slots[slot].pingStatus._bar:SetTexture(UIUtil.SkinnableFile('/game/unit_bmp/bar-0' .. connectionStatus .. '_bmp.dds'))
                    else
                        GUI.slots[slot].pingStatus:Hide()
                    end
                end
            end
            WaitSeconds(1)
        end
    end)

    if not singlePlayer then
        CreateCPUMetricUI()
    end
end

function RefreshOptionDisplayData(scenarioInfo)
    local globalOpts = import('/lua/ui/lobby/lobbyOptions.lua').globalOpts
    local teamOptions = import('/lua/ui/lobby/lobbyOptions.lua').teamOptions
    local AIOpts = import('/lua/ui/lobby/lobbyOptions.lua').AIOpts
    if not scenarioInfo and gameInfo.GameOptions.ScenarioFile and (gameInfo.GameOptions.ScenarioFile ~= "") then
        scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
    end
    formattedOptions = {}
    nonDefaultFormattedOptions = {}

    -- Show a summary of the number of active mods.
    local modStr = false
    local modNum = table.getn(Mods.GetGameMods(gameInfo.GameMods)) or 0
    local modNumUI = table.getn(Mods.GetUiMods()) or 0
    if modNum > 0 and modNumUI > 0 then
        modStr = modNum..' Mods (and '..modNumUI..' UI Mods)'
        if modNum == 1 and modNumUI > 1 then
            modStr = modNum..' Mod (and '..modNumUI..' UI Mods)'
        elseif modNum > 1 and modNumUI == 1 then
            modStr = modNum..' Mods (and '..modNumUI..' UI Mod)'
        elseif modNum == 1 and modNumUI == 1 then
            modStr = modNum..' Mod (and '..modNumUI..' UI Mod)'
        else
            modStr = modNum..' Mods (and '..modNumUI..' UI Mods)'
        end
    elseif modNum > 0 and modNumUI == 0 then
        modStr = modNum..' Mods'
        if modNum == 1 then
            modStr = modNum..' Mod'
        end
    elseif modNum == 0 and modNumUI > 0 then
        modStr = modNumUI..' UI Mods'
        if modNum == 1 then
            modStr = modNumUI..' UI Mod'
        end
    end
    if modStr then
        local option = {
            text = modStr,
            value = LOC('<LOC lobby_0003>Check Mod Manager'),
            mod = true,
            tooltip = 'Lobby_Mod_Option',
            valueTooltip = 'Lobby_Mod_Option'
        }

        table.insert(formattedOptions, option)
        table.insert(nonDefaultFormattedOptions, option)
    end

    -- Update the unit restrictions display.
    if gameInfo.GameOptions.RestrictedCategories ~= nil then
        local restrNum = table.getn(gameInfo.GameOptions.RestrictedCategories)
        if restrNum ~= 0 then
            local restrictLabel
            if restrNum == 1 then -- just 1
                restrictLabel = LOC("<LOC lobui_0415>1 Build Restriction")
            else
                restrictLabel = LOCF("<LOC lobui_0414>%d Build Restrictions", restrNum)
            end

            local option = {
                text = restrictLabel,
                value = LOC("<LOC lobui_0416>Check Unit Manager"),
                mod = true,
                tooltip = 'Lobby_BuildRestrict_Option',
                valueTooltip = 'Lobby_BuildRestrict_Option'
            }

            table.insert(formattedOptions, option)
            table.insert(nonDefaultFormattedOptions, option)
        end
    end

    -- Add an option to the formattedOption lists
    local function addFormattedOption(optData, gameOption)
        -- Don't show multiplayer-only options in single-player
        if optData.mponly and singlePlayer then
            return
        end

        -- Don't bother for options with only one value. These are usually someone trying to do
        -- something clever with a mod or such, not "real" options we care about.
        if table.getn(optData.values) <= 1 then
            return
        end

        local option = {
            text = optData.label,
            tooltip = { text = optData.label, body = optData.help }
        }

        -- Options are stored as keys from the values array in optData. We want to display the
        -- descriptive string in the UI, so let's go dig it out.

        -- Scan the values array to find the one with the key matching our value for that option.
        for k, val in optData.values do
            local key = val.key or val

            if key == gameOption then
                option.key = key
                option.value = val.text or optData.value_text
                option.valueTooltip = {text = optData.label, body = val.help or optData.value_help}

                table.insert(formattedOptions, option)

                -- Add this option to the non-default set for the UI.
                if k ~= optData.default then
                    table.insert(nonDefaultFormattedOptions, option)
                end

                break
            end
        end
    end

    local function addOptionsFrom(optionObject)
        for index, optData in optionObject do
            local gameOption = gameInfo.GameOptions[optData.key]
            addFormattedOption(optData, gameOption)
        end
    end

    -- Add the core options to the formatted option lists
    addOptionsFrom(globalOpts)
    addOptionsFrom(teamOptions)
    addOptionsFrom(AIOpts)

    -- Add options from the scenario object, if any are provided.
    if scenarioInfo.options then
        if not MapUtil.ValidateScenarioOptions(scenarioInfo.options, true) then
            AddChatText('The options included in this map specified invalid defaults. See moholog for details.')
            AddChatText('An arbitrary option has been selected for now: check the game options screen!')
        end

        for index, optData in scenarioInfo.options do
            addFormattedOption(optData, gameInfo.GameOptions[optData.key])
        end
    end

    GUI.OptionContainer:CalcVisible()
end

function wasConnected(peer)
    for _,v in pairs(connectedTo) do
        if v == peer then
            return true
        end
    end
    return false
end

--- Return a status code representing the status of our connection to a peer.
-- @param peer, native table as returned by lobbyComm:GetPeer()
-- @return A value describing the connectivity to given peer.
-- 1 means no connectivity, 2 means they haven't reported that they can talk to us, 3 means
--
-- @todo: This function has side effects despite the naming suggesting that it shouldn't.
--        These need to go away.
function CalcConnectionStatus(peer)
    if peer.status ~= 'Established' then
        return 3
    else
        if not wasConnected(peer.id) then
            local peerSlot = FindSlotForID(peer.id)
            local slot = GUI.slots[peerSlot]
            local playerInfo = gameInfo.PlayerOptions[peerSlot]

            slot.name:SetTitleText(GetPlayerDisplayName(playerInfo))
            slot.name._text:SetFont('Arial Gras', 15)
            if not table.find(ConnectionEstablished, peer.name) then
                if playerInfo.Human and not IsLocallyOwned(peerSlot) then
                    table.insert(ConnectionEstablished, peer.name)
                    for k, v in CurrentConnection do -- Remove PlayerName in this Table
                        if v == peer.name then
                            CurrentConnection[k] = nil
                            break
                        end
                    end
                end
            end

            table.insert(connectedTo, peer.id)
        end
        if not table.find(peer.establishedPeers, lobbyComm:GetLocalPlayerID()) then
            -- they haven't reported that they can talk to us?
            return 1
        end

        local peers = lobbyComm:GetPeers()
        for k,v in peers do
            if v.id ~= peer.id and v.status == 'Established' then
                if not table.find(peer.establishedPeers, v.id) then
                    -- they can't talk to someone we can talk to.
                    return 1
                end
            end
        end
        return 2
    end
end

function EveryoneHasEstablishedConnections(check_observers)
    local important = {}
    for slot, player in gameInfo.PlayerOptions:pairs() do
        if not table.find(important, player.OwnerID) then
            table.insert(important, player.OwnerID)
        end
    end

    if check_observers then
        for slot,observer in gameInfo.Observers:pairs() do
            if not table.find(important, observer.OwnerID) then
                table.insert(important, observer.OwnerID)
            end
        end
    end

    local result = true
    for k, id in important do
        if id ~= localPlayerID then
            local peer = lobbyComm:GetPeer(id)
            for k2, other in important do
                if id ~= other and not table.find(peer.establishedPeers, other) then
                    result = false
                    AddChatText(LOCF("<LOC lobui_0299>%s doesn't have an established connection to %s",
                                     peer.name,
                                     lobbyComm:GetPeer(other).name
                    ))
                end
            end
        end
    end
    return result
end

function AddChatText(text, playerID, scrollToBottom)
    if not GUI.chatDisplay then
        LOG("Can't add chat text -- no chat display")
        LOG("text=" .. repr(text))
        return
    end

    -- local chatPlayerColor = Prefs.GetFromCurrentProfile('ChatPlayerColor')
    -- if chatPlayerColor == nil then
    --   chatPlayerColor = true
    -- end
    
    -- local scrolledToBottom = GUI.chatPanel:IsScrolledToBottom() or scrollToBottom
    -- local nameColor = "AAAAAA" -- Displaying text in grey by default if the player is observer
    -- local textColor = "AAAAAA"
    -- local nameFont = "Arial Gras"
    -- for id, player in gameInfo.PlayerOptions:pairs() do
    --     if player.OwnerID == playerID then
    --         textColor = nil
    --         nameColor = gameColors.PlayerColors[player.PlayerColor]
    --         if not chatPlayerColor then
    --           nameFont = UIUtil.bodyFont
    --             if Prefs.GetOption('faction_font_color') then
    --                 nameColor = import('/lua/skins/skins.lua').skins[ FACTION_NAMES[GetLocalPlayerData():AsTable().Faction] ].fontColor
    --                 textColor = nameColor
    --             else
    --                 nameColor = nil
    --             end
    --         end
    --         break
    --     end
    -- end
    -- local name = FindNameForID(playerID)

    -- GUI.chatDisplay:PostMessage(text, name, {fontColor = textColor}, {fontColor = nameColor, fontFamily = nameFont})
    -- if scrolledToBottom then
    --    GUI.chatPanel:ScrollToBottom()
    -- else
    --    GUI.newMessageArrow:Enable()
    -- end
    GUI.chatDisplay:AppendSystemInfo(text)
end

--- Update a slot display in a single map control.
function RefreshMapPosition(mapCtrl, slotIndex)

    local playerInfo = gameInfo.PlayerOptions[slotIndex]
    local notFixed = gameInfo.GameOptions['TeamSpawn'] ~= 'fixed'

    -- Evil autoteams voodoo.
    if gameInfo.GameOptions.AutoTeams and not gameInfo.AutoTeams[slotIndex] and lobbyComm:IsHost() then
        gameInfo.AutoTeams[slotIndex] = 1
    end

    -- The ACUButton instance representing this slot, if any.
    local marker = mapCtrl.startPositions[slotIndex]
    if marker then
        marker:SetClosed(gameInfo.ClosedSlots[slotIndex])
        if gameInfo.ClosedSlots[slotIndex] and gameInfo.SpawnMex[slotIndex] then
            marker:SetClosedSpawnMex()
        end
    end

    mapCtrl:UpdatePlayer(slotIndex, playerInfo, notFixed)

    -- Nothing more for us to do for a closed or missing slot.
    if gameInfo.ClosedSlots[slotIndex] or not marker then
        return
    end

    if gameInfo.GameOptions.AutoTeams then
        if gameInfo.GameOptions.AutoTeams == 'lvsr' then
            local midLine = mapCtrl.Left() + (mapCtrl.Width() / 2)
            if notFixed then
                local markerPos = marker.Left()
                if markerPos < midLine then
                    marker:SetTeam(2)
                else
                    marker:SetTeam(3)
                end
            end
        elseif gameInfo.GameOptions.AutoTeams == 'tvsb' then
            local midLine = mapCtrl.Top() + (mapCtrl.Height() / 2)
            if notFixed then
                local markerPos = marker.Top()
                if markerPos < midLine then
                    marker:SetTeam(2)
                else
                    marker:SetTeam(3)
                end
            end
        elseif gameInfo.GameOptions.AutoTeams == 'pvsi' then
            if notFixed then
                if math.mod(slotIndex, 2) ~= 0 then
                    marker:SetTeam(2)
                else
                    marker:SetTeam(3)
                end
            end
        elseif gameInfo.GameOptions.AutoTeams == 'manual' and notFixed then
            marker:SetTeam(gameInfo.AutoTeams[slotIndex] or 1)
        end
    end
end

--- Update a single slot in all displayed map controls.
function RefreshMapPositionForAllControls(slot)
    RefreshMapPosition(GUI.mapView, slot)
    if LrgMap and not LrgMap.isHidden then
        RefreshMapPosition(LrgMap.content.mapPreview, slot)
    end
end

function ShowMapPositions(mapCtrl, scenario)
    local playerArmyArray = MapUtil.GetArmies(scenario)

    for inSlot, army in playerArmyArray do
        RefreshMapPosition(mapCtrl, inSlot)
    end
end

function ConfigureMapListeners(mapCtrl, scenario)
    local playerArmyArray = MapUtil.GetArmies(scenario)

    for inSlot, army in playerArmyArray do
        local slot = inSlot -- Closure copy.

        -- The ACUButton instance representing this slot.
        local marker = mapCtrl.startPositions[inSlot]

        marker.OnRollover = function(self, state)
            if state == 'enter' then
                GUI.slots[slot].name.HandleEvent(self, {Type='MouseEnter'})
            elseif state == 'exit' then
                GUI.slots[slot].name.HandleEvent(self, {Type='MouseExit'})
            end
        end

        marker.OnClick = function(self)
            if gameInfo.GameOptions['TeamSpawn'] == 'fixed' then
                if FindSlotForID(localPlayerID) ~= slot and gameInfo.PlayerOptions[slot] == nil then
                    if IsPlayer(localPlayerID) then
                        if lobbyComm:IsHost() then
                            HostUtils.MovePlayerToEmptySlot(FindSlotForID(localPlayerID), slot)
                        else
                            lobbyComm:SendData(hostID, {Type = 'MovePlayer', RequestedSlot = slot})
                        end
                        -- if first click is a not empty slot and second click is a empty slot: reset vars
                        if mapPreviewSlotSwap == true then
                            mapPreviewSlotSwap = false
                            mapPreviewSlotSwapFrom = 0
                        end
                    elseif IsObserver(localPlayerID) then
                        if lobbyComm:IsHost() then
                            local requestedFaction = GetSanitisedLastFaction()
                            HostUtils.ConvertObserverToPlayer(FindObserverSlotForID(localPlayerID), slot)
                        else
                            lobbyComm:SendData(
                                hostID,
                                {
                                    Type = 'RequestConvertToPlayer',
                                    ObserverSlot = FindObserverSlotForID(localPlayerID),
                                    PlayerSlot = slot
                                }
                            )
                        end
                    end
                else -- swap players on map preview
                    if lobbyComm:IsHost() and mapPreviewSlotSwap == false  then
                        mapPreviewSlotSwapFrom = slot
                        mapPreviewSlotSwap = true
                    elseif lobbyComm:IsHost() and mapPreviewSlotSwap == true and mapPreviewSlotSwapFrom ~= slot then
                        mapPreviewSlotSwap = false
                        DoSlotBehavior(mapPreviewSlotSwapFrom, 'move_player_to_slot' .. slot, '')
                        mapPreviewSlotSwapFrom = 0
                    end
                end
            else
                if gameInfo.GameOptions.AutoTeams and lobbyComm:IsHost() then
                    -- Handle the manual-mode reassignment of slots to teams.
                    if gameInfo.GameOptions.AutoTeams == 'manual' then
                        if not gameInfo.ClosedSlots[slot] and (gameInfo.PlayerOptions[slot] or gameInfo.GameOptions['TeamSpawn'] ~= 'fixed') then
                            local targetTeam
                            if gameInfo.AutoTeams[slot] == 7 then
                                -- 2 here corresponds to team 1, since a team value of 1 represents
                                -- "no team". Apparently GPG really, really didn't like zero.
                                targetTeam = 2
                            else
                                targetTeam = gameInfo.AutoTeams[slot] + 1
                            end

                            marker:SetTeam(targetTeam)
                            gameInfo.AutoTeams[slot] = targetTeam

                            lobbyComm:BroadcastData(
                                {
                                    Type = 'AutoTeams',
                                    Slot = slot,
                                    Team = gameInfo.AutoTeams[slot],
                                }
                            )
                            gameInfo.PlayerOptions[slot]['Team'] = gameInfo.AutoTeams[slot]
                            SetSlotInfo(slot, gameInfo.PlayerOptions[slot])
                            UpdateGame()
                        end
                    end
                end
            end
        end

        if lobbyComm:IsHost() then
            marker.OnRightClick = function(self)
                if gameInfo.SpawnMex[slot] then
                    HostUtils.SetSlotClosed(slot, false)
                elseif gameInfo.ClosedSlots[slot] then
                    if gameInfo.AdaptiveMap then
                        HostUtils.SetSlotClosedSpawnMex(slot)
                    else
                        HostUtils.SetSlotClosed(slot, false)
                    end
                else
                    HostUtils.SetSlotClosed(slot, true)
                end
            end
        end
    end
end

function SendCompleteGameStateToPeer(peerId)
    lobbyComm:SendData(peerId, {Type = 'GameInfo', GameInfo = GameInfo.Flatten(gameInfo)})
end

function UpdateClientModStatus(newHostSimMods)
    -- Apply the new game mods from the host, but don't touch our UI mod configuration.
    selectedSimMods = newHostSimMods

    -- Make sure none of our selected UI mods are blacklisted
    local bannedMods = CheckModCompatability()
    if not table.empty(bannedMods) then
        WarnIncompatibleMods()

        selectedUIMods = SetUtils.Subtract(selectedUIMods, bannedMods)
    end

    Mods.SetSelectedMods(SetUtils.Union(selectedSimMods, selectedUIMods))
end

-- LobbyComm Callbacks
function InitLobbyComm(protocol, localPort, desiredPlayerName, localPlayerUID, natTraversalProvider)
    lobbyComm = LobbyComm.CreateLobbyComm(protocol, localPort, desiredPlayerName, localPlayerUID, natTraversalProvider)

    if not lobbyComm then
        error('Failed to create lobby using port ' .. tostring(localPort))
    end

    lobbyComm.ConnectionFailed = function(self, reason)
        LOG("CONNECTION FAILED " .. reason)
        GUI.connectionFailedDialog = UIUtil.ShowInfoDialog(GUI.panel, LOCF(Strings.ConnectionFailed, Strings[reason] or reason),
                                                           "<LOC _OK>", ReturnToMenu)

        lobbyComm:Destroy()
        lobbyComm = nil
    end

    lobbyComm.LaunchFailed = function(self,reasonKey)
        AddChatText(LOC(Strings[reasonKey] or reasonKey))
    end

    lobbyComm.Ejected = function(self,reason)
        LOG("EJECTED " .. reason)

        GUI.connectionFailedDialog = UIUtil.ShowInfoDialog(GUI, LOCF(Strings.Ejected, Strings[reason] or reason), "<LOC _OK>", ReturnToMenu)
        lobbyComm:Destroy()
        lobbyComm = nil
    end

    lobbyComm.ConnectionToHostEstablished = function(self,myID,myName,theHostID)
        LOG("CONNECTED TO HOST")
        hostID = theHostID
        localPlayerID = myID
        localPlayerName = myName

        lobbyComm:SendData(hostID, { Type = 'SetAvailableMods', Mods = Mods.GetLocallyAvailableMods(), Name = localPlayerName})

        lobbyComm:SendData(hostID,
            {
                Type = 'AddPlayer',
                PlayerOptions = GetLocalPlayerData():AsTable()
            }
        )

        -- Update, if needed, and broadcast, your CPU benchmark value.
        if not singlePlayer then
            ForkThread(function() UpdateBenchmark() end)
        end

        local function KeepAliveThreadFunc()
            local threshold = LobbyComm.quietTimeout
            local active = true
            local prev = 0
            while lobbyComm do
                local host = lobbyComm:GetPeer(hostID)
                if active and host.quiet > threshold then
                    active = false
                    local function OnRetry()
                        host = lobbyComm:GetPeer(hostID)
                        threshold = host.quiet + LobbyComm.quietTimeout
                        active = true
                    end
                    UIUtil.QuickDialog(GUI, "<LOC lobui_0266>Connection to host timed out.",
                                            "<LOC lobui_0267>Keep Trying", OnRetry,
                                            "<LOC lobui_0268>Give Up", ReturnToMenu,
                                            nil, nil,
                                            true,
                                            {worldCover = false, escapeButton = 2})
                elseif host.quiet < prev then
                    threshold = LobbyComm.quietTimeout
                end
                prev = host.quiet
                WaitSeconds(1)
            end
        end -- KeepAliveThreadFunc

        GUI.keepAliveThread = ForkThread(KeepAliveThreadFunc)
        CreateUI(LobbyComm.maxPlayerSlots)
    end

    lobbyComm.DataReceived = function(self,data)
        -- Messages anyone can receive
        if data.Type == 'PlayerOptions' then
            local options = data.Options

            for key, val in options do
                -- The host *is* allowed to set options on slots he doesn't own, of course.
                if data.SenderID ~= hostID then
                    if key == 'Team' and gameInfo.GameOptions['AutoTeams'] ~= 'none' then
                        WARN("Attempt to set Team while Auto Teams are on.")
                        return false
                    elseif gameInfo.PlayerOptions[data.Slot].OwnerID ~= data.SenderID then
                        WARN("Attempt to set option on unowned slot.")
                        return false
                    end
                end

                gameInfo.PlayerOptions[data.Slot][key] = val
                if lobbyComm:IsHost() then
                    local playerInfo = gameInfo.PlayerOptions[data.Slot]
                    if playerInfo.Human then
                        GpgNetSend('PlayerOption', playerInfo.OwnerID, key, val)
                    else
                        GpgNetSend('AIOption', playerInfo.PlayerName, key, val)
                    end

                    -- TODO: This should be a global listener on PlayerData objects, but I'm in too
                    -- much pain to implement that listener system right now. EVIL HACK TIME
                    if key == "Ready" then
                        HostUtils.RefreshButtonEnabledness()
                    end
                    -- DONE.
                end
            end
            SetSlotInfo(data.Slot, gameInfo.PlayerOptions[data.Slot])
        elseif data.Type == 'PublicChat' then
            GUI.chatDisplay:AppendPlayerMessage(data.SenderName, data.Text)
            --AddChatText("["..data.SenderName.."] "..data.Text)
        elseif data.Type == 'PrivateChat' then
            GUI.chatDisplay:AppendPrivateMessage(data.SenderName, localPlayerName, data.Text)
            --AddChatText("<<"..LOCF("<LOC lobui_0442>From %s", data.SenderName)..">> "..data.Text)
        elseif data.Type == 'CPUBenchmark' then
            -- CPU benchmark code
            local newInfo = false
            if data.PlayerName and CPU_Benchmarks[data.PlayerName] ~= data.Result then
                newInfo = true
            end

            local benchmarks = {}
            if data.PlayerName then
                benchmarks[data.PlayerName] = data.Result
            else
                benchmarks = data.Benchmarks
            end

            for name, result in benchmarks do
                CPU_Benchmarks[name] = result
                local id = FindIDForName(name)
                local slot = FindSlotForID(id)
                if slot then
                    SetSlotCPUBar(slot, gameInfo.PlayerOptions[slot])
                else
                    refreshObserverList()
                end
            end

            -- Host broadcasts new CPU benchmark information to give the info to clients that are not directly connected to data.PlayerName yet.
            if lobbyComm:IsHost() and newInfo then
                lobbyComm:BroadcastData({Type='CPUBenchmark', Benchmarks=CPU_Benchmarks})
            end

            -- Refilter the players after benchmark
            KyrosLobby.PlayerFilters:Filter()
        elseif data.Type == 'SetPlayerNotReady' then
            EnableSlot(data.Slot)
            GUI.becomeObserver:Enable()

            SetPlayerOption(data.Slot, 'Ready', false)
        elseif data.Type == 'AutoTeams' then
            gameInfo.AutoTeams[data.Slot] = data.Team
            gameInfo.PlayerOptions[data.Slot]['Team'] = data.Team
            SetSlotInfo(data.Slot, gameInfo.PlayerOptions[data.Slot])
            UpdateGame()
        end

        if lobbyComm:IsHost() then
            -- Host only messages
            if data.Type == 'AddPlayer' then
                -- try to reassign the same slot as in the last game if it's a rehosted game, otherwise give it an empty
                -- slot or move it to observer
                SendCompleteGameStateToPeer(data.SenderID)

                if argv.isRehost then
                    local rehostSlot = FindRehostSlotForID(data.SenderID) or 0
                    if rehostSlot ~= 0 and gameInfo.PlayerOptions[rehostSlot] then
                        -- If the slot is occupied, the occupying player will be moved away or to observer. If it's an
                        -- AI, it will be removed
                        local occupyingPlayer = gameInfo.PlayerOptions[rehostSlot]
                        if not occupyingPlayer.Human then
                            HostUtils.RemoveAI(rehostSlot)
                            HostUtils.TryAddPlayer(data.SenderID, rehostSlot, PlayerData(data.PlayerOptions))
                        else
                            HostUtils.ConvertPlayerToObserver(rehostSlot, true)
                            HostUtils.TryAddPlayer(data.SenderID, rehostSlot, PlayerData(data.PlayerOptions))
                            HostUtils.ConvertObserverToPlayer(FindObserverSlotForID(occupyingPlayer.OwnerID))
                        end
                    else
                        HostUtils.TryAddPlayer(data.SenderID, rehostSlot, PlayerData(data.PlayerOptions))
                    end
                else
                    HostUtils.TryAddPlayer(data.SenderID, 0, PlayerData(data.PlayerOptions))
                end
                PlayVoice(Sound{Bank = 'XGG',Cue = 'XGG_Computer__04716'}, true)
            elseif data.Type == 'MovePlayer' then
                local CurrentSlot = FindSlotForID(data.SenderID)
                -- Handle ready-races.
                if gameInfo.PlayerOptions[CurrentSlot].Ready then
                    return
                end
                -- Player requests to be moved to a different empty slot.
                HostUtils.MovePlayerToEmptySlot(CurrentSlot, data.RequestedSlot)

            elseif data.Type == 'RequestConvertToObserver' then
                HostUtils.ConvertPlayerToObserver(data.RequestedSlot)
            elseif data.Type == 'RequestConvertToPlayer' then
                HostUtils.ConvertObserverToPlayer(data.ObserverSlot, data.PlayerSlot)
            elseif data.Type == 'RequestColor' then
                if IsColorFree(data.Color) then
                    -- Color is available, let everyone else know
                    SetPlayerColor(gameInfo.PlayerOptions[data.Slot], data.Color)
                    lobbyComm:BroadcastData({ Type = 'SetColor', Color = data.Color, Slot = data.Slot })
                    SetSlotInfo(data.Slot, gameInfo.PlayerOptions[data.Slot])
                else
                    -- Sorry, it's not free. Force the player back to the color we have for him.
                    lobbyComm:SendData(data.SenderID, { Type = 'SetColor', Color =
                    gameInfo.PlayerOptions[data.Slot].PlayerColor, Slot = data.Slot })
                end
            elseif data.Type == 'ClearSlot' then
                if gameInfo.PlayerOptions[data.Slot].OwnerID == data.SenderID then
                    HostUtils.RemoveAI(data.Slot)
                else
                    WARN("Attempt to clear unowned slot")
                end
            elseif data.Type == 'SetAvailableMods' then
                availableMods[data.SenderID] = data.Mods
                HostUtils.UpdateMods(data.SenderID, data.Name)
            elseif data.Type == 'MissingMap' then
                HostUtils.PlayerMissingMapAlert(data.Id)
            end
        else -- Non-host only messages
            if data.Type == 'SystemMessage' then
                PrintSystemMessage(data.Id, data.Args)
            elseif data.Type == 'SetAllPlayerNotReady' then
                if not IsPlayer(localPlayerID) then
                    return
                end
                local localSlot = FindSlotForID(localPlayerID)
                EnableSlot(localSlot)
                GUI.becomeObserver:Enable()
                SetPlayerOption(localSlot, 'Ready', false)
            elseif data.Type == 'Peer_Really_Disconnected' then
                if data.Observ == false then
                    gameInfo.PlayerOptions[data.Slot] = nil
                elseif data.Observ == true then
                    gameInfo.Observers[data.Slot] = nil
                end
                AddChatText(LOCF("<LOC Engine0003>Lost connection to %s.", data.Options.PlayerName), "Engine0003")
                ClearSlotInfo(data.Slot)
                UpdateGame()
            elseif data.Type == 'SlotAssigned' then
                gameInfo.PlayerOptions[data.Slot] = PlayerData(data.Options)
                PlayVoice(Sound{Bank = 'XGG',Cue = 'XGG_Computer__04716'}, true)
                SetSlotInfo(data.Slot, gameInfo.PlayerOptions[data.Slot])
                UpdateFactionSelectorForPlayer(gameInfo.PlayerOptions[data.Slot])
                PossiblyAnnounceGameFull()
                -- Move to the prefered slot
                KyrosLobby:MoveToPreferedSlot(data.Slot)
            elseif data.Type == 'SlotMove' then
                gameInfo.PlayerOptions[data.OldSlot] = nil
                gameInfo.PlayerOptions[data.NewSlot] = PlayerData(data.Options)
                ClearSlotInfo(data.OldSlot)
                SetSlotInfo(data.NewSlot, gameInfo.PlayerOptions[data.NewSlot])
                UpdateFactionSelectorForPlayer(gameInfo.PlayerOptions[data.NewSlot])
            elseif data.Type == 'SwapPlayers' then
                DoSlotSwap(data.Slot1, data.Slot2)
            elseif data.Type == 'ObserverAdded' then
                gameInfo.Observers[data.Slot] = PlayerData(data.Options)
                refreshObserverList()
            elseif data.Type == 'ConvertObserverToPlayer' then
                gameInfo.Observers[data.OldSlot] = nil
                gameInfo.PlayerOptions[data.NewSlot] = PlayerData(data.Options)
                refreshObserverList()
                SetSlotInfo(data.NewSlot, gameInfo.PlayerOptions[data.NewSlot])
                UpdateFactionSelectorForPlayer(gameInfo.PlayerOptions[data.NewSlot])
            elseif data.Type == 'ConvertPlayerToObserver' then
                gameInfo.Observers[data.NewSlot] = PlayerData(data.Options)
                gameInfo.PlayerOptions[data.OldSlot] = nil
                ClearSlotInfo(data.OldSlot)
                refreshObserverList()
                UpdateFactionSelectorForPlayer(gameInfo.Observers[data.NewSlot])
            elseif data.Type == 'SetColor' then
                SetPlayerColor(gameInfo.PlayerOptions[data.Slot], data.Color)
                SetSlotInfo(data.Slot, gameInfo.PlayerOptions[data.Slot])
            elseif data.Type == 'GameInfo' then
                -- Completely update the game state. To be used exactly once: when first connecting.
                local hostFlatInfo = data.GameInfo
                gameInfo = GameInfo.CreateGameInfo(LobbyComm.maxPlayerSlots, hostFlatInfo)

                UpdateClientModStatus(gameInfo.GameMods, true)
                UpdateGame()
            elseif data.Type == 'GameOptions' then
                for key, value in data.Options do
                    gameInfo.GameOptions[key] = value
                end

                UpdateGame()
            elseif data.Type == 'Launch' then
                local info = data.GameInfo
                info.GameMods = Mods.GetGameMods(info.GameMods)
                SetWindowedLobby(false)

                -- Evil hack to correct the skin for randomfaction players before launch.
                for index, player in info.PlayerOptions do
                    -- Set the skin to the faction you'll be playing as, whatever that may be. (prevents
                    -- random-faction people from ending up with something retarded)
                    if player.OwnerID == localPlayerID then
                        UIUtil.SetCurrentSkin(FACTION_NAMES[player.Faction])
                    end
                 end

                SavePresetToName(LAST_GAME_PRESET_NAME)
                lobbyComm:LaunchGame(info)
            elseif data.Type == 'ClearSlot' then
                gameInfo.PlayerOptions[data.Slot] = nil
                ClearSlotInfo(data.Slot)
            elseif data.Type == 'ModsChanged' then
                gameInfo.GameMods = data.GameMods

                UpdateClientModStatus(data.GameMods)
                UpdateGame()
                import('/lua/ui/lobby/ModsManager.lua').UpdateClientModStatus(gameInfo.GameMods)
            elseif data.Type == 'SlotClosed' then
                gameInfo.ClosedSlots[data.Slot] = data.Closed
                gameInfo.SpawnMex[data.Slot] = false
                ClearSlotInfo(data.Slot)
            elseif data.Type == 'SlotClosedSpawnMex' then
                gameInfo.ClosedSlots[data.Slot] = data.ClosedSpawnMex
                gameInfo.SpawnMex[data.Slot] = data.ClosedSpawnMex
                ClearSlotInfo(data.Slot)
            end
        end
    end

    lobbyComm.SystemMessage = function(self, text)
        AddChatText(text)
    end

    lobbyComm.GameLaunched = function(self)
        local player = lobbyComm:GetLocalPlayerID()
        for i, v in gameInfo.PlayerOptions do
            if v.Human and v.OwnerID == player then
                Prefs.SetToCurrentProfile('LoadingFaction', v.Faction)
                break
            end
        end

        GpgNetSend('GameState', 'Launching')
        if GUI.pingThread then
            KillThread(GUI.pingThread)
        end
        if GUI.keepAliveThread then
            KillThread(GUI.keepAliveThread)
        end
        GUI:Destroy()
        GUI = false
        MenuCommon.MenuCleanup()
        lobbyComm:Destroy()
        lobbyComm = false

        -- determine if cheat keys should be mapped
        if not DebugFacilitiesEnabled() then
            IN_ClearKeyMap()
            IN_AddKeyMapTable(import('/lua/keymap/keymapper.lua').GetKeyMappings(gameInfo.GameOptions['CheatsEnabled']=='true'))
        end
    end

    lobbyComm.Hosting = function(self)
        InitHostUtils()

        localPlayerID = lobbyComm:GetLocalPlayerID()
        hostID = localPlayerID
        HostUtils.UpdateMods()

        --- Returns true if the given option has the given key as a valid setting.
        local function keyIsValidForOption(option, key)
            for k, v in option.values do
                if v.key == key or v == key then
                    return true
                end
            end
            return false
        end

        -- Given an option key, find the value stored in the profile (if any) and assign either it,
        -- or that option's default value, to the current game state.
        local setOptionsFromPref = function(option)
            local defValue = Prefs.GetFromCurrentProfile("LobbyOpt_" .. option.key)

            -- Do the slightly stupid thing to check if the option we found in the profile is
            -- a valid key for this option. Some mods muck about with the possibilities, so we
            -- need to make sure we use a sane default if that's happened.
            if defValue == nil or not keyIsValidForOption(option, defValue) then
                -- Exception to make AllowObservers work because the engine requires
                -- the keys to be bool. Custom options should use 'True' or 'False'
                if option.key == 'AllowObservers' then
                    defValue = option.values[option.default].key
                else
                    defValue = option.values[option.default].key or option.values[option.default]
                end
            end

            SetGameOption(option.key, defValue, true)
        end

        -- Give myself the first slot
        local myPlayerData = GetLocalPlayerData()

        gameInfo.PlayerOptions[1] = myPlayerData

        -- set default lobby values
        for index, option in globalOpts do
            setOptionsFromPref(option)
        end

        for index, option in teamOpts do
            setOptionsFromPref(option)
        end

        for index, option in AIOpts do
            setOptionsFromPref(option)
        end

        -- The key, LastScenario, is referred to from GPG code we don't hook.
        if not self.desiredScenario or self.desiredScenario == "" then
            self.desiredScenario = Prefs.GetFromCurrentProfile("LastScenario")
        end
        local scenarioInfo = MapUtil.LoadScenario(self.desiredScenario)
        if not scenarioInfo or scenarioInfo.type != UIUtil.requiredType then
            self.desiredScenario = UIUtil.defaultScenario
        end
        SetGameOption('ScenarioFile', self.desiredScenario, true)

        GUI.keepAliveThread = ForkThread(
        -- Eject players who haven't sent a heartbeat in a while
        function()
            while true and lobbyComm do
                local peers = lobbyComm:GetPeers()
                for k,peer in peers do
                    if peer.quiet > LobbyComm.quietTimeout then
                        lobbyComm:EjectPeer(peer.id,'TimedOutToHost')
                        -- %s timed out.
                        SendSystemMessage("lobui_0205", peer.name)

                        -- Search and Remove the peer disconnected
                        for k, v in CurrentConnection do
                            if v == peer.name then
                                CurrentConnection[k] = nil
                                break
                            end
                        end
                        for k, v in ConnectionEstablished do
                            if v == peer.name then
                                ConnectionEstablished[k] = nil
                                break
                            end
                        end
                        for k, v in ConnectedWithProxy do
                            if v == peer.id then
                                ConnectedWithProxy[k] = nil
                                break
                            end
                        end
                    end
                end
                WaitSeconds(1)
            end
        end
        )

        CreateUI(LobbyComm.maxPlayerSlots)
        if not singlePlayer then
            ForkThread(function() UpdateBenchmark() end)
        end

        if argv.isRehost then
            LoadPresetByName(LAST_GAME_PRESET_NAME);

            local rehostSlot = FindRehostSlotForID(localPlayerID)
            if rehostSlot then
                HostUtils.MovePlayerToEmptySlot(1, rehostSlot)
            end

            for index, playerInfo in ipairs(rehostPlayerOptions) do
                if not playerInfo.Human then
                    HostUtils.AddAI(playerInfo.PlayerName, playerInfo.AIPersonality, playerInfo.StartSpot)
                end
            end
        end

        UpdateGame()
        KyrosLobby:MoveToPreferedSlot(1)
    end

    lobbyComm.PeerDisconnected = function(self,peerName,peerID)

         -- Search and Remove the peer disconnected
        for k, v in CurrentConnection do
            if v == peerName then
                CurrentConnection[k] = nil
                break
            end
        end
        for k, v in ConnectionEstablished do
            if v == peerName then
                ConnectionEstablished[k] = nil
                break
            end
        end
        for k, v in ConnectedWithProxy do
            if v == peerID then
                ConnectedWithProxy[k] = nil
                break
            end
        end

        if IsPlayer(peerID) then
            local slot = FindSlotForID(peerID)
            if slot and lobbyComm:IsHost() then
                PlayVoice(Sound{Bank = 'XGG',Cue = 'XGG_Computer__04717'}, true)
                lobbyComm:BroadcastData(
                {
                    Type = 'Peer_Really_Disconnected',
                    Options =  gameInfo.PlayerOptions[slot]:AsTable(),
                    Slot = slot,
                    Observ = false,
                }
                )
                ClearSlotInfo(slot)
                gameInfo.PlayerOptions[slot] = nil
                UpdateGame()
            end
        elseif IsObserver(peerID) then
            local slot2 = FindObserverSlotForID(peerID)
            if slot2 and lobbyComm:IsHost() then
                lobbyComm:BroadcastData(
                {
                    Type = 'Peer_Really_Disconnected',
                    Options =  gameInfo.Observers[slot2]:AsTable(),
                    Slot = slot2,
                    Observ = true,
                }
                )
                gameInfo.Observers[slot2] = nil
                UpdateGame()
            end
        end

        availableMods[peerID] = nil
        if HostUtils.UpdateMods then
            HostUtils.UpdateMods()
        end
    end

    lobbyComm.GameConfigRequested = function(self)
        return {
            Options = gameInfo.GameOptions,
            HostedBy = localPlayerName,
            PlayerCount = GetPlayerCount(),
            GameName = gameName,
            ProductCode = import('/lua/productcode.lua').productCode,
        }
    end
end

function SetPlayerOptions(slot, options, ignoreRefresh)
    if not IsLocallyOwned(slot) and not lobbyComm:IsHost() then
        WARN("Hey you can't set a player option on a slot you don't own:")
        for key, val in options do
            WARN("(slot:"..tostring(slot).." / key:"..tostring(key).." / val:"..tostring(val)..")")
        end
        return
    end

    for key, val in options do
        gameInfo.PlayerOptions[slot][key] = val
    end

    lobbyComm:BroadcastData(
    {
        Type = 'PlayerOptions',
        Options = options,
        Slot = slot,
    })

    if not ignoreRefresh then
        UpdateGame()
    end
end

function SetPlayerOption(slot, key, val, ignoreRefresh)
    local options = {}
    options[key] = val
    SetPlayerOptions(slot, options, ignoreRefresh)
end

function SetGameOptions(options, ignoreRefresh)
    if not lobbyComm:IsHost() then
        WARN('Attempt to set game option by a non-host')
        return
    end

    for key, val in options do
        Prefs.SetToCurrentProfile('LobbyOpt_' .. key, val)
        gameInfo.GameOptions[key] = val

        -- don't want to send all restricted categories to gpgnet, so just send bool
        -- note if more things need to be translated to gpgnet, a translation table would be a better implementation
        -- but since there's only one, we'll call it out here
        if key == 'RestrictedCategories' then
            local restrictionsEnabled = false
            if val ~= nil then
                if table.getn(val) ~= 0 then
                    restrictionsEnabled = true
                end
            end
            GpgNetSend('GameOption', key, restrictionsEnabled)
        elseif key == 'ScenarioFile' then
            -- Special-snowflake the LastScenario key (used by GPG code).
            Prefs.SetToCurrentProfile('LastScenario', val)
            GpgNetSend('GameOption', key, val)
            if gameInfo.GameOptions.ScenarioFile and (gameInfo.GameOptions.ScenarioFile ~= '') then
                -- Warn about attempts to load nonexistent maps.
                if not DiskGetFileInfo(gameInfo.GameOptions.ScenarioFile) then
                    AddChatText('The selected map does not exist.')
                else
                    local scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
                    if scenarioInfo and scenarioInfo.map and (scenarioInfo.map ~= '') then
                        GpgNetSend('GameOption', 'Slots', table.getsize(scenarioInfo.Configurations.standard.teams[1].armies))
                    end
                end
            end
        else
            GpgNetSend('GameOption', key, val)
        end
    end

    lobbyComm:BroadcastData {
        Type = 'GameOptions',
        Options = options
    }

    if not ignoreRefresh then
        UpdateGame()
    end
end

function SetGameOption(key, val, ignoreRefresh)
    local options = {}
    options[key] = val
    SetGameOptions(options, ignoreRefresh)
end

function DebugDump()
    if lobbyComm then
        lobbyComm:DebugDump()
    end
end

-- Perform one-time setup of the large map preview
function CreateBigPreview(parent)
    if LrgMap then
        LrgMap.isHidden = false
        RefreshLargeMap()
        LrgMap:Show()
        return
    end

    -- Size of the map preview to generate.
    local MAP_PREVIEW_SIZE = 721

    -- The size of the mass/hydrocarbon icons
    local HYDROCARBON_ICON_SIZE = 14
    local MASS_ICON_SIZE = 10

    local dialogContent = Group(parent)
    dialogContent.Width:Set(MAP_PREVIEW_SIZE + 10)
    dialogContent.Height:Set(MAP_PREVIEW_SIZE + 10)

    LrgMap = Popup(parent, dialogContent)

    -- The LrgMap shouldn't be destroyed due to issues related to texture pooling. Evil hack ensues.
    local onTryMapClose = function()
        LrgMap:Hide()
        LrgMap.isHidden = true
    end
    LrgMap.OnEscapePressed = onTryMapClose
    LrgMap.OnShadowClicked = onTryMapClose

    -- Create the map preview
    local mapPreview = ResourceMapPreview(dialogContent, MAP_PREVIEW_SIZE, MASS_ICON_SIZE, HYDROCARBON_ICON_SIZE)
    dialogContent.mapPreview = mapPreview
    LayoutHelpers.AtCenterIn(mapPreview, dialogContent)

    local closeBtn = UIUtil.CreateButtonStd(dialogContent, '/dialogs/close_btn/close')
    LayoutHelpers.AtRightTopIn(closeBtn, dialogContent, 1, 1)
    closeBtn.OnClick = onTryMapClose

    -- Keep the close button on top of the border (which is itself on top of the map preview)
    LayoutHelpers.DepthOverParent(closeBtn, mapPreview, 2)

    RefreshLargeMap()
end

-- Refresh the large map preview (so it can update if something changes while it's open)
function RefreshLargeMap()
    if not LrgMap or LrgMap.isHidden then
        return
    end

    local scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
    LrgMap.content.mapPreview:SetScenario(scenarioInfo, true)
    ConfigureMapListeners(LrgMap.content.mapPreview, scenarioInfo)
    ShowMapPositions(LrgMap.content.mapPreview, scenarioInfo)
end

--------------------------------------------------
--  Ping GUI Functions
--------------------------------------------------

local ConnectionStatusInfo = {
    '<LOC lobui_0454>Player is not connected to someone',
    '<LOC lobui_0455>Connected',
    '<LOC lobui_0456>Not Connected',
    '<LOC lobui_0457>No connection info available',
}

function Ping_AddControlTooltip(control, delay, slotNumber)
    --This function creates the Ping tooltip for a slot along with necessary mouseover function.
    --It is called during the UI creation.
    --    control: The control to which the tooltip is to be added.
    --    delay: Amount of time to delay before showing tooltip.  See Tooltip.CreateMouseoverDisplay for info.
    --  slotNumber: The slot number associated with the control.
    local pingText = function()
        local pingInfo
        if GUI.slots[slotNumber].pingStatus.PingActualValue then
            pingInfo = GUI.slots[slotNumber].pingStatus.PingActualValue
        else
            pingInfo = LOC('<LOC lobui_0458>UnKnown')
        end
        return LOC('<LOC lobui_0452>Ping: ') .. pingInfo
    end
    local pingBody = function()
        local conInfo
        if GUI.slots[slotNumber].pingStatus.ConnectionStatus then
            conInfo = GUI.slots[slotNumber].pingStatus.ConnectionStatus
        else
            conInfo = 4
        end
        return LOC('<LOC lobui_0453>Only shows when > 500') .. '\n\n' .. LOC(ConnectionStatusInfo[conInfo])
    end
    Lobby_AddControlTooltip(control,
                            delay,
                            slotNumber,
                            pingText,
                            pingBody)
end

function Lobby_AddControlTooltip(control, delay, slotNumber, displayText, displayBody)
    if not control.oldHandleEvent then
        control.oldHandleEvent = control.HandleEvent
    end
    control.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
            local slot = slotNumber
            Tooltip.CreateMouseoverDisplay(self, {text= displayText(),
            body=displayBody()}, delay, true)
        elseif event.Type == 'MouseExit' then
            Tooltip.DestroyMouseoverDisplay()
        end
        return self.oldHandleEvent(self, event)
    end
end

--CPU Status Bar Configuration
local greenBarMax = 300
local yellowBarMax = 375
local scoreSkew1 = 0 --Skews all CPU scores up or down by the amount specified (0 = no skew)
local scoreSkew2 = 1.0 --Skews all CPU scores specified coefficient (1.0 = no skew)

--Variables for CPU Test
local BenchTime

--------------------------------------------------
--  CPU Benchmarking Functions
--------------------------------------------------
function CPUBenchmark()
    --This function gives the CPU some busy work to do.
    --CPU score is determined by how quickly the work is completed.
    local totalTime = 0
    local lastTime
    local currTime
    local countTime = 0
    --Make everything a local variable
    --This is necessary because we don't want LUA searching through the globals as part of the benchmark
    local h
    local i
    local j
    local k
    local l
    local m
    for h = 1, 48, 1 do
        -- If the need for the benchmark no longer exists, abort it now.
        if not lobbyComm then
            return
        end

        lastTime = GetSystemTimeSeconds()
        for i = 1.0, 25.0, 0.0008 do
            --This instruction set should cover most LUA operators
            j = i + i   --Addition
            k = i * i   --Multiplication
            l = k / j   --Division
            m = j - i   --Subtraction
            j = i ^ 4   --Power
            l = -i      --Negation
            m = {'One', 'Two', 'Three'} --Create Table
            table.insert(m, 'Four')     --Insert Table Value
            table.remove(m, 1)          --Remove Table Value
            l = table.getn(m)           --Get Table Length
            k = i < j   --Less Than
            k = i == j  --Equality
            k = i <= j  --Less Than or Equal to
            k = not k
        end
        currTime = GetSystemTimeSeconds()
        totalTime = totalTime + currTime - lastTime

        if totalTime > countTime then
            --This is necessary in order to make this 'thread' yield so other things can be done.
            countTime = totalTime + .125
            WaitSeconds(0)
        end
    end
    BenchTime = math.ceil(totalTime * 100)
end

--------------------------------------------------
--  CPU GUI Functions
--------------------------------------------------
function CreateCPUMetricUI()
    GUI.rerunBenchmark.OnClick = function(self, modifiers)
            ForkThread(function() UpdateBenchmark(true) end)
    end
end

function CPU_AddControlTooltip(control, delay, slotNumber)
    --This function creates the benchmark tooltip for a slot along with necessary mouseover function.
    --It is called during the UI creation.
    --    control: The control to which the tooltip is to be added.
    --    delay: Amount of time to delay before showing tooltip.  See Tooltip.CreateMouseoverDisplay for info.
    --  slotNumber: The slot number associated with the control.
    local CPUText = function()
        local CPUInfo
        if GUI.slots[slotNumber].CPUSpeedBar.CPUActualValue then
            CPUInfo = GUI.slots[slotNumber].CPUSpeedBar.CPUActualValue
        else
            CPUInfo = LOC('<LOC lobui_0458>UnKnown')
        end
        return LOC('<LOC lobui_0459>CPU Rating: ') .. CPUInfo
    end
    local CPUBody = function()
        return LOC('<LOC lobui_0322>0=Fastest, 450=Slowest')
    end
    Lobby_AddControlTooltip(control,
                            delay,
                            slotNumber,
                            CPUText,
                            CPUBody)
end

--- Get the CPU benchmark score for the local machine.
-- If a previously-calculated benchmark score is found in the profile, it is returned immediately.
-- Otherwise, a fresh score is calculated and stored (enjoy the lag!).
--
-- @param force If truthy, a fresh score is always calculated.
-- @return A benchmark score between 0 and 450, or nil if StressCPU returned nil (which occurs iff
--         the lobby is exited before the calculation is complete. Callers should abort gracefully
--         in this situation).
-- @see StressCPU
function GetBenchmarkScore(force)
    local wait = 10
    local benchmark

    if force then
        wait = 0
    else
        benchmark = GetPreference('CPUBenchmark')
    end

    if not benchmark then
        -- We defer the calculation by 10s here because, often, non-forced requests are occurring on
        -- startup, and we want to give other tasks, such as connection negotiation, a fighting
        -- chance of completing before we ruin everything.
        --
        -- Benchmark scores are associated with the machine, not the profile: hence SetPreference.

        benchmark = StressCPU(wait)
        SetPreference('CPUBenchmark', benchmark)
    end

    return benchmark
end

--- Updates the displayed benchmark score for the local player.
--
-- @param force Passed as the `force` parameter to GetBenchmarkScore.
-- @see GetBenchmarkScore
function UpdateBenchmark(force)
    local benchmark = GetBenchmarkScore(force)

    if benchmark then
        CPU_Benchmarks[localPlayerName] = benchmark
        lobbyComm:BroadcastData({ Type = 'CPUBenchmark', PlayerName = localPlayerName, Result = benchmark })
        if FindObserverSlotForID(localPlayerID) then
            refreshObserverList()
        else
            UpdateCPUBar(localPlayerName)
        end
    end
end

-- This function instructs the PC to do a CPU score benchmark.
-- It handles the necessary UI updates during the benchmark, sends
-- the benchmark result to other players when finished, and it updates the local
-- user's UI with their new result.
--    waitTime: The delay in seconds that this function should wait before starting the benchmark.
function StressCPU(waitTime)
    GUI.rerunBenchmark:Disable()
    for i = waitTime, 1, -1 do
        GUI.rerunBenchmark.label:SetText(i..'s')
        WaitSeconds(1)

        -- lobbyComm is destroyed when the lobby is exited. If the user left the lobby, we no longer
        -- want to run the benchmark (it just introduces lag as the user is trying to do something
        -- else.
        if not lobbyComm then
            return
        end
    end

    --Get our last benchmark (if there was one)
    local currentBestBenchmark = 10000

    GUI.rerunBenchmark.label:SetText('. . .')

    --Run three benchmarks and keep the best one
    for i=1, 3, 1 do
        BenchTime = 0
        CPUBenchmark()

        BenchTime = scoreSkew2 * BenchTime + scoreSkew1

        -- The bench might have yeilded to a launcher, so we verify the lobbyComm is available when
        -- we need it in a moment here (as well as aborting if we're wasting our time more than usual)
        if not lobbyComm then
            return
        end

        --If this benchmark was better than our best so far...
        if BenchTime < currentBestBenchmark then
            currentBestBenchmark = BenchTime
        end
    end

    --Reset Button UI
    GUI.rerunBenchmark:Enable()
    GUI.rerunBenchmark.label:SetText('')

    return currentBestBenchmark
end

function UpdateCPUBar(playerName)
    --This function updates the UI with a CPU benchmark bar for the specified playerName.
    --    playerName: The name of the player whose benchmark should be updated.
    local playerId = FindIDForName(playerName)
    local playerSlot = FindSlotForID(playerId)
    if playerSlot ~= nil then
        SetSlotCPUBar(playerSlot, gameInfo.PlayerOptions[playerSlot])
    end
end

function SetSlotCPUBar(slot, playerInfo)
    --This function updates the UI with a CPU benchmark bar for the specified slot/playerInfo.
    --    slot: a numbered slot (1-however many slots there are for this map)
    --    playerInfo: The corresponding playerInfo object from gameInfo.PlayerOptions[slot].


    if GUI.slots[slot].CPUSpeedBar then
        GUI.slots[slot].CPUSpeedBar:Hide()
        if playerInfo.Human then
            local b = CPU_Benchmarks[playerInfo.PlayerName]
            if b then
                -- For display purposes, the bar has a higher minimum that the actual barMin value.
                -- This is to ensure that the bar is visible for very small values

                -- Lock values to the largest possible result.
                if b > GUI.slots[slot].CPUSpeedBar.barMax then
                    b = GUI.slots[slot].CPUSpeedBar.barMax
                end

                GUI.slots[slot].CPUSpeedBar:SetValue(b)
                GUI.slots[slot].CPUSpeedBar.CPUActualValue = b

                GUI.slots[slot].CPUSpeedBar:Show()
            end
        end
    end
end

function SetGameTitleText(title)
    GUI.titleText:SetColor("B9BFB9")
    if title == '' then
        title = LOC("<LOC lobui_0427>FAF Game Lobby")
    end
    GUI.titleText:SetText(title)
end

function ShowTitleDialog()
    CreateInputDialog(GUI, "Game Title",
        function(self, text)
            SetGameOption("Title", text, true)
            SetGameTitleText(text)
        end, gameInfo.GameOptions.Title
)
end

-- Rule title
function SetRuleTitleText(rule)
    GUI.RuleLabel:SetColors("B9BFB9")
    if rule == '' then
        if lobbyComm:IsHost() then
            GUI.RuleLabel:SetColors("FFCC00")
            rule = LOC("<LOC lobui_0420>No Rules: Click to add rules")
        else
            rule = "No rules."
        end
    end

    GUI.RuleLabel:SetText(rule)
end

-- Show the rule change dialog.
function ShowRuleDialog()
    CreateInputDialog(GUI, "Game Rules",
        function(self, text)
            SetGameOption("GameRules", text, true)
            SetRuleTitleText(text)
        end
)
end

-- Faction selector
function CreateUI_Faction_Selector(lastFaction)
    -- Build a list of button objects from the list of defined factions. Each faction will use the
    -- faction key as its RadioButton texture path offset.
    local buttons = {}
    for i, faction in FactionData.Factions do
        buttons[i] = {
            texturePath = faction.Key
        }
    end

    -- Special-snowflaking for the random faction.
    table.insert(buttons, {
        texturePath = "random"
    })

    local factionSelector = RadioButton(GUI.panel, "/factionselector/", buttons, lastFaction, true)
    GUI.factionSelector = factionSelector
    LayoutHelpers.AtLeftTopIn(factionSelector, GUI.panel, 407, 20)
    factionSelector.OnChoose = function(self, targetFaction, key)
        local localSlot = FindSlotForID(localPlayerID)
        local slotFactionIndex = GetSlotFactionIndex(targetFaction)
        Prefs.SetToCurrentProfile('LastFaction', targetFaction)
        GUI.slots[localSlot].faction:SetItem(slotFactionIndex)
        SetPlayerOption(localSlot, 'Faction', slotFactionIndex)
        gameInfo.PlayerOptions[localSlot].Faction = slotFactionIndex

        RefreshLobbyBackground(targetFaction)
        UIUtil.SetCurrentSkin(FACTION_NAMES[targetFaction])
    end

    -- Only enable all buttons incase all the buttons are disabled, to avoid overriding partially disabling of the buttons
    factionSelector.Enable = function(self)
        for k, v in self.mButtons do
            if v._controlState == "up" then
                return
            end
        end
        for k, v in self.mButtons do
            v:Enable()
        end
    end

    factionSelector.SetCheck = function(self, index)
        for i,button in self.mButtons do
            if index ==i then
                button:SetCheck(true)
            else
                button:SetCheck(false)
            end
        end
        self.mCurSelection = index
    end

    factionSelector.EnableSpecificButtons = function(self, specificButtons)
        for i,button in self.mButtons do
            if specificButtons[i] then
                button:Enable()
            else
                button:Disable()
            end
        end
    end
end

function UpdateFactionSelectorForPlayer(playerInfo)
    if playerInfo.OwnerID == localPlayerID then
        UpdateFactionSelector()
    end
end

function UpdateFactionSelector()
    local playerSlotID = FindSlotForID(localPlayerID)
    local playerSlot = GUI.slots[playerSlotID]
    if not playerSlot or not playerSlot.AvailableFactions or gameInfo.PlayerOptions[playerSlotID].Ready then
        UIUtil.setEnabled(GUI.factionSelector, false)
        return
    end
    local enabledList = {}
    for index,button in GUI.factionSelector.mButtons do
        enabledList[index] = false
        for i,value in playerSlot.AvailableFactions do
            if value == allAvailableFactionsList[index] then
                if gameInfo.PlayerOptions[playerSlotID].Faction == i then
                    GUI.factionSelector:SetCheck(index)
                end
                enabledList[index] = true
                break
            end
        end
    end
    GUI.factionSelector:EnableSpecificButtons(enabledList)
end

function GetSlotFactionIndex(factionIndex)
    local localSlot = GUI.slots[FindSlotForID(localPlayerID)]
    local actualFaction = allAvailableFactionsList[factionIndex]
    for index,value in localSlot.AvailableFactions do
        if value == actualFaction then
            return index
        end
    end
end

function RefreshLobbyBackground(faction)
    local LobbyBackground = Prefs.GetFromCurrentProfile('LobbyBackground') or 1
    if GUI.background then
        GUI.background:Destroy()
    end
    if LobbyBackground == 1 then -- Factions
        faction = faction or GetSanitisedLastFaction()
        if FACTION_NAMES[faction] then
            GUI.background = Bitmap(GUI, "/textures/ui/common/BACKGROUND/faction/faction-background-paint_" .. FACTION_NAMES[faction] .. "_bmp.dds")
        else
            return
        end
    elseif LobbyBackground == 2 then -- Concept art
        GUI.background = Bitmap(GUI, "/textures/ui/common/BACKGROUND/art/art-background-paint0" .. math.random(1, 5) .. "_bmp.dds")
    elseif LobbyBackground == 3 then -- Screenshot
        GUI.background = Bitmap(GUI, "/textures/ui/common/BACKGROUND/scrn/scrn-background-paint" .. math.random(1, 14) .. "_bmp.dds")
    elseif LobbyBackground == 4 then -- Map
        local MapPreview = import('/lua/ui/controls/mappreview.lua').MapPreview
        GUI.background = MapPreview(GUI) -- Background map
        if gameInfo.GameOptions.ScenarioFile and (gameInfo.GameOptions.ScenarioFile ~= '') then
            local scenarioInfo = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile)
            if scenarioInfo and scenarioInfo.map and (scenarioInfo.map ~= '') and scenarioInfo.preview then
                if not GUI.background:SetTexture(scenarioInfo.preview) then
                    GUI.background:SetTextureFromMap(scenarioInfo.map)
                end
            end
        end
    elseif LobbyBackground == 5 then -- None
        return
    end

    local LobbyBackgroundStretch = Prefs.GetFromCurrentProfile('LobbyBackgroundStretch') or 'true'
    LayoutHelpers.AtCenterIn(GUI.background, GUI)
    LayoutHelpers.DepthUnderParent(GUI.background, GUI.panel)
    if LobbyBackgroundStretch == 'true' then
        LayoutHelpers.FillParent(GUI.background, GUI)
    else
        LayoutHelpers.FillParentPreserveAspectRatio(GUI.background, GUI)
    end
end

function ShowLobbyOptionsDialog()
    local dialogContent = Group(GUI)
    dialogContent.Width:Set(420)
    dialogContent.Height:Set(260)

    local dialog = Popup(GUI, dialogContent)
    GUI.lobbyOptionsDialog = dialog

    local buttons = {
        {
            label = LOC("<LOC lobui_0406>") -- Factions
        },
        {
            label = LOC("<LOC lobui_0407>")  -- Concept art
        },
        {
            label = LOC("<LOC lobui_0408>") -- Screenshot
        },
        {
            label = LOC("<LOC lobui_0409>") -- Map
        },
        {
            label = LOC("<LOC lobui_0410>") -- None
        }
    }

    -- Label shown above the background mode selection radiobutton.
    local backgroundLabel = UIUtil.CreateText(dialogContent, LOC("<LOC lobui_0405> "), 16, 'Arial', true)
    local selectedBackgroundState = Prefs.GetFromCurrentProfile("LobbyBackground") or 1
    local backgroundRadiobutton = RadioButton(dialogContent, '/RADIOBOX/', buttons, selectedBackgroundState, false, true)

    LayoutHelpers.AtLeftTopIn(backgroundLabel, dialogContent, 15, 15)
    LayoutHelpers.AtLeftTopIn(backgroundRadiobutton, dialogContent, 15, 40)

    backgroundRadiobutton.OnChoose = function(self, index, key)
        Prefs.SetToCurrentProfile("LobbyBackground", index)
        RefreshLobbyBackground()
    end
    -- label for displaying chat font size
    local currentFontSize = Prefs.GetFromCurrentProfile('LobbyChatFontSize') or 14
    local slider_Chat_SizeFont_TEXT = UIUtil.CreateText(dialogContent, LOC("<LOC lobui_0404> ").. currentFontSize, 14, 'Arial', true)
    LayoutHelpers.AtRightTopIn(slider_Chat_SizeFont_TEXT, dialogContent, 27, 162)

    -- slider for changing chat font size
    local slider_Chat_SizeFont = Slider(dialogContent, false, 9, 20,
        UIUtil.SkinnableFile('/slider02/slider_btn_up.dds'), 
        UIUtil.SkinnableFile('/slider02/slider_btn_over.dds'), 
        UIUtil.SkinnableFile('/slider02/slider_btn_down.dds'), 
        UIUtil.SkinnableFile('/slider02/slider-back_bmp.dds'))
        LayoutHelpers.AtRightTopIn(slider_Chat_SizeFont, dialogContent, 20, 182)
    slider_Chat_SizeFont:SetValue(currentFontSize)
    slider_Chat_SizeFont.OnValueChanged = function(self, newValue)
        -- local isScrolledDown = GUI.chatPanel:IsScrolledToBottom()
    
        -- local sliderValue = math.floor(self._currentValue())
        -- slider_Chat_SizeFont_TEXT:SetText(LOC("<LOC lobui_0404> ").. sliderValue)
       
        -- Prefs.SetToCurrentProfile('LobbyChatFontSize', sliderValue)
        -- -- updating chat panel with new font size
        -- GUI.chatPanel:SetLinesPerScrollPage(sliderValue)
        -- GUI.chatPanel:SetFont(nil, sliderValue)
     
        -- if isScrolledDown then
        --     GUI.chatPanel:ScrollToBottom()
        -- end
    end
    --
    local cbox_WindowedLobby = UIUtil.CreateCheckbox(dialogContent, '/CHECKBOX/', LOC("<LOC lobui_0402>Windowed mode"))
    LayoutHelpers.AtRightTopIn(cbox_WindowedLobby, dialogContent, 20, 42)
    Tooltip.AddCheckboxTooltip(cbox_WindowedLobby, {text=LOC('<LOC lobui_0402>Windowed mode'), body=LOC("<LOC lobui_0403>")})
    cbox_WindowedLobby.OnCheck = function(self, checked)
        local option
        if checked then
            option = 'true'
        else
            option = 'false'
        end
        Prefs.SetToCurrentProfile('WindowedLobby', option)
        SetWindowedLobby(checked)
    end
    --
    local cbox_StretchBG = UIUtil.CreateCheckbox(dialogContent, '/CHECKBOX/', LOC("<LOC lobui_0400>Stretch Background"))
    LayoutHelpers.AtRightTopIn(cbox_StretchBG, dialogContent, 20, 68)
    Tooltip.AddCheckboxTooltip(cbox_StretchBG, {text=LOC('<LOC lobui_0400>Stretch Background'), body=LOC("<LOC lobui_0401>")})
    cbox_StretchBG.OnCheck = function(self, checked)
        if checked then
            Prefs.SetToCurrentProfile('LobbyBackgroundStretch', 'true')
        else
            Prefs.SetToCurrentProfile('LobbyBackgroundStretch', 'false')
        end
        RefreshLobbyBackground()
    end
    
    local cbox_FactionFontColor = UIUtil.CreateCheckbox(dialogContent, '/CHECKBOX/', LOC("<LOC lobui_0411>Faction Font Color"))
    LayoutHelpers.AtRightTopIn(cbox_FactionFontColor, dialogContent, 20, 94)
    cbox_FactionFontColor.OnCheck = function(self, checked)
        if checked then
            Prefs.SetOption('faction_font_color', true)
        else
            Prefs.SetOption('faction_font_color', false)
        end
        UIUtil.UpdateCurrentSkin()
    end
    -- Quit button
    local QuitButton = UIUtil.CreateButtonWithDropshadow(dialogContent, '/BUTTON/medium/', LOC("<LOC _Close>Close"))
    LayoutHelpers.AtHorizontalCenterIn(QuitButton, dialogContent, 0)
    LayoutHelpers.AtBottomIn(QuitButton, dialogContent, 10)

    QuitButton.OnClick = function(self)
        dialog:Hide()
    end
    --
    local WindowedLobby = Prefs.GetFromCurrentProfile('WindowedLobby') or 'true'
    cbox_WindowedLobby:SetCheck(WindowedLobby == 'true', true)
    if defaultMode == 'windowed' then
        -- Already set Windowed in Game
        cbox_WindowedLobby:Disable()
    end
    --
    local lobbyBackgroundStretch = Prefs.GetFromCurrentProfile('LobbyBackgroundStretch') or 'true'
    cbox_StretchBG:SetCheck(lobbyBackgroundStretch == 'true', true)
    --
    local factionFontColor = Prefs.GetOption('faction_font_color')
    cbox_FactionFontColor:SetCheck(factionFontColor == true, true)

    local chatPlayerColor = Prefs.GetFromCurrentProfile('ChatPlayerColor')
    cbox_ChatPlayerColor:SetCheck(chatPlayerColor == true or chatPlayerColor == nil, true)
end

-- Load and return the current list of presets from persistent storage.
function LoadPresetsList()
    return Prefs.GetFromCurrentProfile("LobbyPresets") or {}
end

-- Write the given list of preset profiles to persistent storage.
function SavePresetsList(list)
    Prefs.SetToCurrentProfile("LobbyPresets", list)
    SavePreferences()
end

--- Delegate to UIUtil's CreateInputDialog, adding the ridiculus chatEdit hack.
function CreateInputDialog(parent, title, listener, str)
    UIUtil.CreateInputDialog(parent, title, listener, GUI.chatEdit, str)
end

-- Show the lobby preset UI.
function ShowPresetDialog()
    local dialogContent = Group(GUI)
    dialogContent.Width:Set(600)
    dialogContent.Height:Set(530)

    local presetDialog = Popup(GUI, dialogContent)
    presetDialog.OnClosed = presetDialog.Destroy
    GUI.presetDialog = presetDialog

    -- Title
    local titleText = UIUtil.CreateText(dialogContent, LOC('<LOC tooltipui0694>Lobby Presets'), 17, 'Arial Gras', true)
    LayoutHelpers.AtHorizontalCenterIn(titleText, dialogContent, 0)
    LayoutHelpers.AtTopIn(titleText, dialogContent, 10)

    -- Preset List
    local PresetList = ItemList(dialogContent)
    PresetList:SetFont(UIUtil.bodyFont, 14)
    PresetList:ShowMouseoverItem(true)
    PresetList.Width:Set(265)
    PresetList.Height:Set(430)
    LayoutHelpers.DepthOverParent(PresetList, dialogContent, 10)
    LayoutHelpers.AtLeftIn(PresetList, dialogContent, 14)
    LayoutHelpers.AtTopIn(PresetList, dialogContent, 38)
    UIUtil.CreateLobbyVertScrollbar(PresetList, 2)

    -- Info List
    local InfoList = ItemList(dialogContent)
    InfoList:SetFont(UIUtil.bodyFont, 11)
    InfoList:SetColors(nil, "00000000")
    InfoList:ShowMouseoverItem(true)
    InfoList.Width:Set(281)
    InfoList.Height:Set(430)
    LayoutHelpers.RightOf(InfoList, PresetList, 26)

    -- Quit button
    local QuitButton = UIUtil.CreateButtonStd(dialogContent, '/dialogs/close_btn/close')
    LayoutHelpers.AtRightIn(QuitButton, dialogContent, 1)
    LayoutHelpers.AtTopIn(QuitButton, dialogContent, 1)

    -- Load button
    local LoadButton = UIUtil.CreateButtonWithDropshadow(dialogContent, '/BUTTON/medium/', "<LOC _Load>Load")
    LayoutHelpers.AtLeftIn(LoadButton, dialogContent, -2)
    LayoutHelpers.AtBottomIn(LoadButton, dialogContent, 10)
    LoadButton:Disable()

    -- Create button. Occupies the same space as the load button, when available.
    local CreateButton = UIUtil.CreateButtonWithDropshadow(dialogContent, '/BUTTON/medium/', "<LOC _Create>Create")
    LayoutHelpers.RightOf(CreateButton, LoadButton, 28)

    -- Save button
    local SaveButton = UIUtil.CreateButtonWithDropshadow(dialogContent, '/BUTTON/medium/', "<LOC _Save>Save")
    LayoutHelpers.RightOf(SaveButton, CreateButton, 28)
    SaveButton:Disable()

    -- Delete button
    local DeleteButton = UIUtil.CreateButtonWithDropshadow(dialogContent, '/BUTTON/medium/', "<LOC _Delete>Delete")
    LayoutHelpers.RightOf(DeleteButton, SaveButton, 28)
    DeleteButton:Disable()

    LoadButton.OnClick = function(self)
        LoadPreset(PresetList:GetSelection() + 1)
    end

    QuitButton.OnClick = function(self)
        presetDialog:Hide()
    end

    CreateButton.OnClick = function(self)
        local dialogComplete = function(self, presetName)
            if not presetName or presetName == "" then
                return
            end
            local profiles = LoadPresetsList()
            table.insert(profiles, GetPresetFromSettings(presetName))
            SavePresetsList(profiles)

            RefreshAvailablePresetsList(PresetList)

            PresetList:SetSelection(0)
            PresetList:OnClick(0)
        end

        CreateInputDialog(GUI, "<LOC tooltipui0704>Select name for new preset", dialogComplete)
    end

    SaveButton.OnClick = function(self)
        local selectedPreset = PresetList:GetSelection() + 1

        SavePreset(selectedPreset)
        ShowPresetDetails(selectedPreset, InfoList)
    end

    DeleteButton.OnClick = function(self)
        local profiles = LoadPresetsList()

        -- Converting between zero-based indexing in the list and the table indexing...
        table.remove(profiles, PresetList:GetSelection() + 1)

        SavePresetsList(profiles)
        RefreshAvailablePresetsList(PresetList)

        -- And clear the detail view.
        InfoList:DeleteAllItems()
    end

    -- Called when the selected item in the preset list changes.
    local onListItemChanged = function(self, row)
        ShowPresetDetails(row + 1, InfoList)
        LoadButton:Enable()
        SaveButton:Enable()
        DeleteButton:Enable()
    end

    -- Because GPG's event model is painfully retarded..
    PresetList.OnKeySelect = onListItemChanged
    PresetList.OnClick = function(self, row, event)
        self:SetSelection(row)
        onListItemChanged(self, row)
    end

    PresetList.OnDoubleClick = function(self, row)
        LoadPreset(row + 1)
    end

    -- When the user double-clicks on a metadata field, give them a popup to change its value.
    InfoList.OnDoubleClick = function(self, row)
        -- Closure copy, accounting for zero-based indexing in ItemList.
        local theRow = row + 1

        local nameChanged = function(self, str)
            if str == "" then
                return
            end

            local profiles = LoadPresetsList()
            profiles[theRow].Name = str
            SavePresetsList(profiles)

            -- Update the name displayed in the presets list, preserving selection.
            local lastselect = PresetList:GetSelection()
            RefreshAvailablePresetsList(PresetList)
            PresetList:SetSelection(lastselect)

            ShowPresetDetails(theRow, InfoList)
        end

        if row == 0 then
            CreateInputDialog(GUI, "Rename your preset", nameChanged)
        end
    end

    -- Show the "Double-click to edit" tooltip when the user mouses-over an editable field.
    InfoList.OnMouseoverItem = function(self, row)
        -- Determine which metadata cell they moused-over, if any.
        local metadataType
        -- For now, only name is editable. A nice mechanism to edit game preferences seems plausible.
        if row == 0 then
            metadataType = "Preset name"
        else
            Tooltip.DestroyMouseoverDisplay()
            return
        end

        local tooltip = {
            text = metadataType,
            body = "Double-click to edit"
        }

        Tooltip.CreateMouseoverDisplay(self, tooltip, 0, true)
    end

    RefreshAvailablePresetsList(PresetList)
    if PresetList:GetItemCount() == 0 then
        CreateHelpWindow()
    end
end

function CreateHelpWindow()
    local dialogContent = Group(GUI)
    dialogContent.Width:Set(420)
    dialogContent.Height:Set(225)

    local helpWindow = Popup(GUI, dialogContent)

    -- Help textfield
    local textArea = TextArea(dialogContent, 400, 163)
    LayoutHelpers.AtLeftIn(textArea, dialogContent, 13)
    LayoutHelpers.AtTopIn(textArea, dialogContent, 10)
    textArea:SetText(LOC("<LOC tooltipui0706>This dialog allows you to save a snapshot of the current game configuration and reload it later.\n\nOnce the game settings are as you want them, use the \"Create\" button on this dialog to store it. You can reload the stored configuration by selecting it and pressing the \"Load\" button.\n\nThe \"Save\" button will overwrite a selected existing preset with the current configuration."))

    -- OK button
    local OkButton = UIUtil.CreateButtonWithDropshadow(dialogContent, '/BUTTON/medium/', "Ok")
    LayoutHelpers.AtHorizontalCenterIn(OkButton, dialogContent)
    LayoutHelpers.AtBottomIn(OkButton, dialogContent, 8)
    OkButton.OnClick = function(self)
        helpWindow:Close()
    end
end

-- Refresh list of presets
function RefreshAvailablePresetsList(PresetList)
    local profiles = LoadPresetsList()
    PresetList:DeleteAllItems()

    for k, v in profiles do
        PresetList:AddItem(v.Name)
    end
end

-- Update the right-hand panel of the preset dialog to show the contents of the currently selected
-- profile (passed by name as a parameter)
function ShowPresetDetails(preset, InfoList)
    local profiles = LoadPresetsList()
    InfoList:DeleteAllItems()
    InfoList:AddItem('Preset Name: ' .. profiles[preset].Name)

    if DiskGetFileInfo(profiles[preset].MapPath) then
        InfoList:AddItem('Map: ' .. profiles[preset].MapName)
    else
        InfoList:AddItem('Map: Unavailable (' .. profiles[preset].MapName .. ')')
    end

    InfoList:AddItem('')

    -- For each mod, look up its name and pretty-print it.
    local allMods = Mods.AllMods()
    for modId, v in profiles[preset].GameMods do
        if v then
            InfoList:AddItem('Mod: ' .. allMods[modId].name)
        end
    end

    InfoList:AddItem('')
    InfoList:AddItem('Settings :')
    for k, v in sortedpairs(profiles[preset].GameOptions) do
        InfoList:AddItem('- '..k..' : '..tostring(v))
    end
end

-- Create a preset table representing the current configuration.
function GetPresetFromSettings(presetName)
    -- Since GameOptions may only contain strings and ints, some added tables need to be removed before storing
    local cleanGameOptions = table.copy(gameInfo.GameOptions)
    cleanGameOptions.ClanTags = nil
    cleanGameOptions.Ratings = nil

    -- Since PlayerOptions may only contain strings and ints, some added tables need to be removed before storing
    local cleanPlayerOptions = table.copy(gameInfo.PlayerOptions)
    cleanPlayerOptions.AsTable = nil
    cleanPlayerOptions.isEmpty = nil
    cleanPlayerOptions.pairs = nil
    cleanPlayerOptions.print = nil

    return {
        Name = presetName,
        MapName = MapUtil.LoadScenario(gameInfo.GameOptions.ScenarioFile).name,
        MapPath = gameInfo.GameOptions.ScenarioFile,
        GameOptions = cleanGameOptions,
        GameMods = gameInfo.GameMods,
        PlayerOptions = cleanPlayerOptions
    }
end

-- Load the given preset
function LoadPreset(presetIndex)
    local preset = LoadPresetsList()[presetIndex]
    
    if not preset.GameOptions.RestrictedCategories then
        preset.GameOptions.RestrictedCategories = {}
    end
    
    SetGameOptions(preset.GameOptions, true)

    rehostPlayerOptions = preset.PlayerOptions
    selectedSimMods = preset.GameMods
    HostUtils.UpdateMods()

    if GUI.presetDialog then
        GUI.presetDialog:Hide()
    end
    UpdateGame()
end

function LoadPresetByName(name)
    local presets = LoadPresetsList()
    for index, preset in ipairs(presets) do
        if preset.Name == name then
            LoadPreset(index)
            break
        end
    end
end

-- Write the current settings to the given preset profile index
function SavePreset(index)
    local presets = LoadPresetsList()

    local selectedPreset = index
    presets[selectedPreset] = GetPresetFromSettings(presets[selectedPreset].Name)

    SavePresetsList(presets)
end

function SavePresetToName(presetName)
    local presets = LoadPresetsList()
    local found = false
    for index, preset in ipairs(presets) do
        if preset.Name == presetName then
            presets[index] = GetPresetFromSettings(presetName)
            found = true
            break
        end
    end

    if not found then
        table.insert(presets, GetPresetFromSettings(presetName))
    end

    SavePresetsList(presets)
end

-- Find the key for the given value in a table.
-- Nil keys are not supported.
function indexOf(table, needle)
    for k, v in table do
        if v == needle then
            return k
        end
    end
    return nil
end

-- Update the combobox for the given slot so it correctly shows the set of available colours.
-- causes availableColours[slot] to be repopulated.
function Check_Availaible_Color(slot)
    availableColours[slot] = {}

    -- For each possible colour, scan the slots to try and find it and, if unsuccessful, add it to
    -- the available colour set.
    local allColours = gameColors.PlayerColors
    for k, v in allColours do
        local found = false
        for ii = 1, LobbyComm.maxPlayerSlots do
            -- Skip this slot and empty slots.
            if slot ~= ii and gameInfo.PlayerOptions[ii] then
                if gameInfo.PlayerOptions[ii].PlayerColor == k then
                    found = true
                    break
                end
            end
        end

        if not found then
            availableColours[slot][k] = allColours[k]
        end
    end
    --
    GUI.slots[slot].color:ChangeBitmapArray(availableColours[slot], true)
    GUI.slots[slot].color:SetItem(gameInfo.PlayerOptions[slot].PlayerColor)
end

function CheckModCompatability()
    local blacklistedMods = {}
    for modId, _ in SetUtils.Union(selectedSimMods, selectedUIMods) do
        if ModBlacklist[modId] then
            blacklistedMods[modId] = ModBlacklist[modId]
        end
    end

    return blacklistedMods
end

function WarnIncompatibleMods()
    UIUtil.QuickDialog(GUI,
        "<LOC uimod_0031>Some of your enabled mods are known to cause malfunctions with FAF, so have been disabled. See the mod manager for details - some mods may have newer versions which work.",
        "<LOC _Ok>")
end

function DoSlotSwap(slot1, slot2)
    local player1 = gameInfo.PlayerOptions[slot1]
    local player2 = gameInfo.PlayerOptions[slot2]

    local team_bucket = player1.Team
    player1.Team = player2.Team
    player2.Team = team_bucket

    --Handle faction availability
    KeepSameFactionOrRandom(slot1, slot2, player1)
    KeepSameFactionOrRandom(slot2, slot1, player2)

    gameInfo.PlayerOptions[slot2] = player1
    gameInfo.PlayerOptions[slot1] = player2

    SetSlotInfo(slot2, player1)
    SetSlotInfo(slot1, player2)

    UpdateFactionSelectorForPlayer(player1)
    UpdateFactionSelectorForPlayer(player2)
end

function KeepSameFactionOrRandom(slotFrom, slotTo, player)
    local playerFactionKey = GUI.slots[slotFrom].AvailableFactions[player.Faction]
    --intialize to random, incase oldFaction isn't available
    player.Faction = table.getn(GUI.slots[slotTo].AvailableFactions)
    for index,faction in GUI.slots[slotTo].AvailableFactions do
        if faction == playerFactionKey then
            player.Faction = index
        end
    end
end

local function SendPlayerOption(playerInfo, key, value)
    if playerInfo.Human then
        GpgNetSend('PlayerOption', playerInfo.OwnerID, key, value)
    else
        GpgNetSend('AIOption', playerInfo.PlayerName, key, value)
    end
end

--- Create the HostUtils object, containing host-only functions. By not assigning this for non-host
-- players, we ensure a hard crash should a non-host somehow end up trying to call them, simplifying
-- debugging somewhat (as well as reducing the number of toplevel definitions a fair bit).
-- This is clearly not a security feature.
function InitHostUtils()
    if not lobbyComm:IsHost() then
        WARN(debug.traceback(nil, "Attempt to create HostUtils by non-host."))
        return
    end

    HostUtils = {
        --- Cause a player's ready box to become unchecked.
        --
        -- @param slot The slot number of the target player.
        SetPlayerNotReady = function(slot)
            local slotOptions = gameInfo.PlayerOptions[slot]
            if slotOptions.Ready then
                if not IsLocallyOwned(slot) then
                    lobbyComm:SendData(slotOptions.OwnerID, {Type = 'SetPlayerNotReady', Slot = slot})
                end
                slotOptions.Ready = false
            end
        end,

        SetSlotClosed = function(slot, closed)
            -- Don't close an occupied slot.
            if gameInfo.PlayerOptions[slot] then
                return
            end

            lobbyComm:BroadcastData(
                {
                    Type = 'SlotClosed',
                    Slot = slot,
                    Closed = closed
                }
            )

            gameInfo.ClosedSlots[slot] = closed
            gameInfo.SpawnMex[slot] = false
            ClearSlotInfo(slot)
        end,

        SetSlotClosedSpawnMex = function(slot)
            -- Don't close an occupied slot.
            if gameInfo.PlayerOptions[slot] then
                return
            end

            lobbyComm:BroadcastData(
                {
                    Type = 'SlotClosedSpawnMex',
                    Slot = slot,
                    ClosedSpawnMex = true
                }
            )

            gameInfo.ClosedSlots[slot] = true
            gameInfo.SpawnMex[slot] = true
            ClearSlotInfo(slot)
        end,

        ConvertPlayerToObserver = function(playerSlot, ignoreMsg)
            -- make sure player exists
            if not gameInfo.PlayerOptions[playerSlot] then
                WARN("HostUtils.ConvertPlayerToObserver for nonexistent player in slot " .. tostring(playerSlot))
                return
            end

            -- find a free observer slot
            local index = 1
            while gameInfo.Observers[index] do
                index = index + 1
            end

            HostUtils.SetPlayerNotReady(playerSlot)
            local ownerID = gameInfo.PlayerOptions[playerSlot].OwnerID
            gameInfo.Observers[index] = gameInfo.PlayerOptions[playerSlot]
            gameInfo.PlayerOptions[playerSlot] = nil

            if lobbyComm:IsHost() then
                GpgNetSend('PlayerOption', ownerID, 'Team', -1)
                GpgNetSend('PlayerOption', ownerID, 'Army', -1)
                GpgNetSend('PlayerOption', ownerID, 'StartSpot', -index)
            end

            ClearSlotInfo(playerSlot)
            refreshObserverList()

            -- TODO: can probably avoid transmitting the options map here. The slot number should be enough.
            lobbyComm:BroadcastData(
                {
                    Type = 'ConvertPlayerToObserver',
                    OldSlot = playerSlot,
                    NewSlot = index,
                    Options = gameInfo.Observers[index]:AsTable(),
                }
            )

            if not ignoreMsg then
                -- %s has switched from a player to an observer.
                SendSystemMessage("lobui_0226", gameInfo.Observers[index].PlayerName)
            end

            UpdateGame()
        end,

        ConvertObserverToPlayer = function(fromObserverSlot, toPlayerSlot, ignoreMsg)
            -- If no slot is specified (user clicked "go player" button), select a default.
            if not toPlayerSlot or toPlayerSlot < 1 or toPlayerSlot > numOpenSlots then
                toPlayerSlot = HostUtils.FindEmptySlot()

                -- If it's still -1 (No slots available) check for AIs and evict the first one
                if toPlayerSlot < 1 then
                    for i = 1, numOpenSlots do
                        local slot = gameInfo.PlayerOptions[i]
                        if slot and not slot.Human then
                            HostUtils.RemoveAI(i)
                            toPlayerSlot = i
                            break
                        end
                    end

                    -- There are no AIs and no slots, so break out with a message
                    if toPlayerSlot < 1 and gameInfo.Observers[fromObserverSlot] then
                        SendPersonalSystemMessage(gameInfo.Observers[fromObserverSlot].OwnerID, "lobui_0608")
                        return
                    end
                end
            end

            if not gameInfo.Observers[fromObserverSlot] then -- IF no Observer on the current slot : QUIT
                return
            elseif gameInfo.PlayerOptions[toPlayerSlot] then -- IF Player is in the target slot : QUIT
                return
            elseif gameInfo.ClosedSlots[toPlayerSlot] then -- IF target slot is Closed : QUIT
                return
            end

            local incomingPlayer = gameInfo.Observers[fromObserverSlot]

            -- Give them a default colour if the one they already have isn't free.
            if not IsColorFree(incomingPlayer.PlayerColor) then
                local newColour = GetAvailableColor()
                SetPlayerColor(incomingPlayer, newColour)
            end

            gameInfo.PlayerOptions[toPlayerSlot] = incomingPlayer
            gameInfo.Observers[fromObserverSlot] = nil

            lobbyComm:BroadcastData(
                {
                    Type = 'ConvertObserverToPlayer',
                    OldSlot = fromObserverSlot,
                    NewSlot = toPlayerSlot,
                    Options =  gameInfo.PlayerOptions[toPlayerSlot]:AsTable(),
                }
            )

            if not ignoreMsg then
                -- %s has switched from an observer to player.
                SendSystemMessage("lobui_0227", incomingPlayer.PlayerName)
            end

            refreshObserverList()
            SetSlotInfo(toPlayerSlot, gameInfo.PlayerOptions[toPlayerSlot])

            -- This is far from optimally efficient, as it will SetSlotInfo twice when autoteams is enabled.
            AssignAutoTeams()

            UpdateFactionSelectorForPlayer(gameInfo.PlayerOptions[toPlayerSlot])
        end,

        RemoveAI = function(slot)
            if gameInfo.PlayerOptions[slot].Human then
                WARN('Use EjectPlayer to remove humans')
                return
            end

            gameInfo.PlayerOptions[slot] = nil
            ClearSlotInfo(slot)
            lobbyComm:BroadcastData(
                {
                    Type = 'ClearSlot',
                    Slot = slot,
                }
            )
        end,

        --- Returns false if there's an obvious reason why a slot movement between the two given
        -- slots will fail.
        --
        -- @param moveFrom Slot number to move from
        -- @param moveTo Slot number to move to.
        SanityCheckSlotMovement = function(moveFrom, moveTo)
            if gameInfo.ClosedSlots[moveTo] then
                LOG("HostUtils.MovePlayerToEmptySlot: requested slot " .. moveTo .. " is closed")
                return false
            end

            if moveTo > numOpenSlots or moveTo < 1 then
                LOG("HostUtils.MovePlayerToEmptySlot: requested slot " .. moveTo .. " is out of range")
                return false
            end

            if moveFrom > numOpenSlots or moveFrom < 1 then
                LOG("HostUtils.MovePlayerToEmptySlot: target slot " .. moveFrom .. " is out of range")
                return false
            end

            return true
        end,

        --- Move a player from one slot to another, unoccupied one. Is a no-op if the requested slot
        -- is occupied, closed, or out of range. Races over network may cause this to occur during
        -- normal operation.
        --
        -- @param currentSlot The slot occupied by the player to move
        -- @param requestedSlot The slot to move this player to.
        MovePlayerToEmptySlot = function(currentSlot, requestedSlot)
            -- Bail out early for the stupid cases.
            if not HostUtils.SanityCheckSlotMovement(currentSlot, requestedSlot) then
                return
            end

            -- This one's only specific to moving to an empty slot, naturally.
            if gameInfo.PlayerOptions[requestedSlot] then
                LOG("HostUtils.MovePlayerToEmptySlot: requested slot " .. requestedSlot .. " already occupied")
                return false
            end

            local player = gameInfo.PlayerOptions[currentSlot]

            KeepSameFactionOrRandom(currentSlot, requestedSlot, player)

            gameInfo.PlayerOptions[requestedSlot] = gameInfo.PlayerOptions[currentSlot]
            gameInfo.PlayerOptions[currentSlot] = nil
            ClearSlotInfo(currentSlot)
            SetSlotInfo(requestedSlot, gameInfo.PlayerOptions[requestedSlot])

            lobbyComm:BroadcastData(
                {
                    Type = 'SlotMove',
                    OldSlot = currentSlot,
                    NewSlot = requestedSlot,
                    Options = gameInfo.PlayerOptions[requestedSlot]:AsTable(),
                }
            )

            -- This is far from optimally efficient, as it will SetSlotInfo twice when autoteams is enabled.
            AssignAutoTeams()
        end,

        --- Swap the players in the two given slots.
        --
        -- If the target slot is unoccupied, the player in the first slot is simply moved there.
        -- If the target slot is closed, this is a no-op.
        -- If a player or ai occupies both slots, they are swapped.
        SwapPlayers = function(slot1, slot2)
            -- Bail out early for the stupid cases.
            if not HostUtils.SanityCheckSlotMovement(slot1, slot2) then
                return
            end

            local player1 = gameInfo.PlayerOptions[slot1]
            local player2 = gameInfo.PlayerOptions[slot2]

            -- Unready the move-ee
            if player1.Human then
                HostUtils.SetPlayerNotReady(slot1)
            end

            -- If we're moving onto a blank, take the easy way out.
            if not player2 then
                HostUtils.MovePlayerToEmptySlot(slot1, slot2)
                return
            end

            -- If we're switching with a human, we need to clear their ready state for the move
            if player2.Human then
                HostUtils.SetPlayerNotReady(slot2)
            end

            -- Do the swap on our end
            DoSlotSwap(slot1, slot2)

            -- Tell everyone else to do the swap too
            lobbyComm:BroadcastData(
                {
                    Type = 'SwapPlayers',
                    Slot1 = slot1,
                    Slot2 = slot2,
                }
            )

            -- %s has switched with %s
            SendSystemMessage("lobui_0417", player1.PlayerName, player2.PlayerName)
        end,

        --- Add an observer
        --
        -- @param observerData A PlayerData object representing this observer.
        TryAddObserver = function(senderID, observerData)
            local index = 1
            while gameInfo.Observers[index] do
                index = index + 1
            end

            observerData.PlayerName = lobbyComm:MakeValidPlayerName(senderID, observerData.PlayerName)

            gameInfo.Observers[index] = observerData

            lobbyComm:BroadcastData(
                {
                    Type = 'ObserverAdded',
                    Slot = index,
                    Options = observerData:AsTable(),
                }
            )

            -- %s has joined as an observer.
            SendSystemMessage("lobui_0202", observerData.PlayerName)
            refreshObserverList()
        end,

        --- Attempt to add a player to a slot. If no is available, add them as an observer.
        --
        -- @param senderID The peer ID of the player we're adding.
        -- @param slot The slot to insert the player to. A value of less than 1 indicates "any slot"
        -- @param playerData A PlayerData object representing the player to add.
        TryAddPlayer = function(senderID, slot, playerData)
            -- CPU benchmark code
            if playerData.Human and not singlePlayer then
                lobbyComm:SendData(senderID, {Type='CPUBenchmark', Benchmarks=CPU_Benchmarks})
            end

            local newSlot = slot

            if not slot or slot < 1 or newSlot > numOpenSlots then
                newSlot = HostUtils.FindEmptySlot()
            end

            -- if no slot available, and human, try to make them an observer
            if newSlot == -1 then
                PrivateChat(senderID, LOC("<LOC lobui_0237>No slots available, attempting to make you an observer"))
                if playerData.Human then
                    HostUtils.TryAddObserver(senderID, playerData)
                end
                return
            end

            playerData.PlayerName = lobbyComm:MakeValidPlayerName(senderID, playerData.PlayerName)

            -- if a color is requested, attempt to use that color if available, otherwise, assign first available
            if not IsColorFree(playerData.PlayerColor) then
                SetPlayerColor(playerData, GetAvailableColor())
            end

            gameInfo.PlayerOptions[newSlot] = playerData
            lobbyComm:BroadcastData(
                {
                    Type = 'SlotAssigned',
                    Slot = newSlot,
                    Options = playerData:AsTable(),
                }
            )

            SetSlotInfo(newSlot, gameInfo.PlayerOptions[newSlot])
            -- This is far from optimally efficient, as it will SetSlotInfo twice when autoteams is enabled.
            AssignAutoTeams()
            PossiblyAnnounceGameFull()
            -- Auto-kick
            KyrosLobby.PlayerFilters:Filter(playerData)
        end,

        --- Add an AI to the game in the given slot.
        --
        -- @param name The name to use in the player list for this AI.
        -- @param personality The "personality" key, such as "adaptive" or "easy", for this AI.
        -- @param slot (optional) The slot into which to put this AI. Defaults to the first empty
        --                        slot from the top of the list.
        AddAI = function(name, personality, slot)
            HostUtils.TryAddPlayer(hostID, slot, GetAIPlayerData(name, personality))
        end,

        PlayerMissingMapAlert = function(id)
            local slot = FindSlotForID(id)
            local name
            local needMessage = false
            if slot then
                name = gameInfo.PlayerOptions[slot].PlayerName
                if not gameInfo.PlayerOptions[slot].BadMap then
                    needMessage = true
                end
                gameInfo.PlayerOptions[slot].BadMap = true
            else
                slot = FindObserverSlotForID(id)
                if slot then
                    name = gameInfo.Observers[slot].PlayerName
                    if not gameInfo.Observers[slot].BadMap then
                        needMessage = true
                    end
                    gameInfo.Observers[slot].BadMap = true
                end
            end

            if needMessage then
                -- %s is missing map %s.
                SendSystemMessage("lobui_0330", name, gameInfo.GameOptions.ScenarioFile)
                LOG('>> '..name..' is missing map '..gameInfo.GameOptions.ScenarioFile)
                if name == localPlayerName then
                    LOG('>> '..gameInfo.GameOptions.ScenarioFile..' replaced with '.. UIUtil.defaultScenario)
                    SetGameOption('ScenarioFile', UIUtil.defaultScenario)
                end
            end
        end,

        -- This function is needed because army numbers need to be calculated: armies are numbered incrementally in slot order.
        -- Call this function once just before game starts
        SendArmySettingsToServer = function()
            local armyIdx = 1
            local MAXSLOT = 16
            for slotNum = 1, MAXSLOT do
                local playerInfo = gameInfo.PlayerOptions[slotNum]
                if playerInfo ~= nil then
                    LOG('>> SendArmySettingsToServer: Setting army '..armyIdx..' for slot '..slotNum)
                    SendPlayerOption(playerInfo, 'Army', armyIdx)
                    armyIdx = armyIdx + 1
                else
                    LOG('>> SendArmySettingsToServer: Slot '..slotNum..' empty')
                end
            end
        end,

        --- Send player settings to the server
        SendPlayerSettingsToServer = function(slotNum)
            local playerInfo = gameInfo.PlayerOptions[slotNum]
            SendPlayerOption(playerInfo, 'Faction', playerInfo.Faction)
            SendPlayerOption(playerInfo, 'Color', playerInfo.PlayerColor)
            SendPlayerOption(playerInfo, 'Team', playerInfo.Team)
            SendPlayerOption(playerInfo, 'StartSpot', slotNum)
        end,

        --- Called by the host when someone's readyness state changes to update the enabledness of buttons.
        RefreshButtonEnabledness = function()
            -- disable options when all players are marked ready
            -- Is at least one person not ready?
            local playerNotReady = GetPlayersNotReady() ~= false

            -- Host should be able to set game options even if he is observer if all slots are AI
            local hostObserves = false
            if not playerNotReady and IsObserver(localPlayerID) then
                hostObserves = true
            end

            local buttonState = hostObserves or playerNotReady

            UIUtil.setEnabled(GUI.gameoptionsButton, buttonState)
            UIUtil.setEnabled(GUI.defaultOptions, buttonState)
            UIUtil.setEnabled(GUI.randMap, buttonState)
            UIUtil.setEnabled(GUI.autoTeams, buttonState)
            UIUtil.setEnabled(GUI.restrictedUnitsOrPresetsBtn, buttonState)

            -- Launch button enabled if everyone is ready.
            UIUtil.setEnabled(GUI.launchGameButton, singlePlayer or hostObserves or not playerNotReady)
        end,

        -- Update our local gameInfo.GameMods from selected map name and selected mods, then
        -- notify other clients about the change.
        UpdateMods = function(newPlayerID, newPlayerName)
            local newmods = {}
            local missingmods = {}
            local blacklistedMods = {}

            -- If any of our active sim mods are blacklisted, warn the user, turn them off, and
            -- go through the "mods changed" handler code again with the smaller set.
            local bannedMods = CheckModCompatability()
            if not table.empty(bannedMods) then
                WarnIncompatibleMods()

                selectedSimMods = SetUtils.Subtract(selectedSimMods, bannedMods)
                selectedUIMods = SetUtils.Subtract(selectedUIMods, bannedMods)
                OnModsChanged(selectedSimMods, selectedUIMods)

                return
            end

            for modId, _ in selectedSimMods do
                if IsModAvailable(modId) then
                    newmods[modId] = true
                else
                    table.insert(missingmods, modId)
                end
            end

            -- We were called to update the sim mod set for the game, and have _really_ made changes
            if not table.equal(gameInfo.GameMods, newmods) and not newPlayerID then
                gameInfo.GameMods = newmods
                lobbyComm:BroadcastData { Type = "ModsChanged", GameMods = gameInfo.GameMods }
                local nummods = 0
                local uids = ""

                for k in gameInfo.GameMods do
                    nummods = nummods + 1
                    if uids == "" then
                        uids =  k
                    else
                        uids = string.format("%s %s", uids, k)
                    end

                end
                GpgNetSend('GameMods', "activated", nummods)

                if nummods > 0 then
                    GpgNetSend('GameMods', "uids", uids)
                end
            elseif not table.equal(gameInfo.GameMods, newmods) and newPlayerID then
                local modnames = ""
                local totalMissing = table.getn(missingmods)
                local totalListed = 0
                if totalMissing > 0 then
                    for index, id in missingmods do
                        for k,mod in Mods.GetGameMods() do
                            if mod.uid == id then
                                totalListed = totalListed + 1
                                if totalMissing == totalListed then
                                    modnames = modnames .. " " .. mod.name
                                else
                                    modnames = modnames .. " " .. mod.name .. " + "
                                end
                            end
                        end
                    end
                end
                local reason = (LOCF('<LOC lobui_0588>You were automaticly removed from the lobby because you ' ..
                        'don\'t have the following mod(s):\n%s \nPlease, install the mod before you join the game lobby',
                    modnames))
                -- TODO: Verify this functionality
                if FindNameForID(newPlayerID) then
                    AddChatText(FindNameForID(newPlayerID)..' kicked because he does not have this mod : '..modnames)
                else
                    if newPlayerName then
                        AddChatText(newPlayerName..' kicked because he does not have this mod : '..modnames)
                    else
                        AddChatText('The last player is kicked because he does not have this mod : '..modnames)
                    end
                end
                lobbyComm:EjectPeer(newPlayerID, reason)
            end
        end,

        --- Find and return the id of an unoccupied slot.
        --
        -- @return The id of an empty slot, of -1 if none is available.
        FindEmptySlot = function()
            for i = 1, numOpenSlots do
                if not gameInfo.PlayerOptions[i] and not gameInfo.ClosedSlots[i] then
                    return i
                end
            end

            return -1
        end,

        KickObservers = function(reason)
            for k,observer in gameInfo.Observers:pairs() do
                lobbyComm:EjectPeer(observer.OwnerID, reason or "KickedByHost")
            end
            gameInfo.Observers = WatchedValueArray(LobbyComm.maxPlayerSlots)
        end
    }
end
