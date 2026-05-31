-- Locales/Locale-enUS.lua
-- Default locale. Loaded first; every other locale falls back through this table.

local ADDON, ns = ...
ns.L = ns.L or setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

-- Generic
L["WGB"]                          = "WGB"
L["Warmane Group Builder"]        = "Warmane Group Builder"
L["Loaded"]                       = "loaded"
L["Version"]                      = "Version"

-- Slash command help
L["SLASH_HELP_HEADER"]            = "|cFFFF8000Warmane Group Builder|r commands:"
L["SLASH_HELP_TOGGLE"]            = "/wgb - toggle main window"
L["SLASH_HELP_HELP"]              = "/wgb help - print commands"
L["SLASH_HELP_ADVERT"]            = "/wgb advert - send advertisement now"
L["SLASH_HELP_START"]             = "/wgb start - enable auto-invite + auto-repeat"
L["SLASH_HELP_STOP"]              = "/wgb stop - disable auto-invite + auto-repeat"
L["SLASH_HELP_LOCK"]              = "/wgb lock - stop accepting new invites"
L["SLASH_HELP_KICK"]              = "/wgb kick <name> - kick player"
L["SLASH_HELP_APPROVE"]           = "/wgb approve <name> - approve player"
L["SLASH_HELP_CONFIG"]            = "/wgb config - open config panel"
L["SLASH_HELP_RESET"]             = "/wgb reset - reset settings"
L["SLASH_HELP_DEBUG"]             = "/wgb debug - toggle debug output  |  /wgb debug dump - print current state"

-- Roles
L["ROLE_TANK"]                    = "Tank"
L["ROLE_HEAL"]                    = "Healer"
L["ROLE_RDPS"]                    = "Ranged DPS"
L["ROLE_MDPS"]                    = "Melee DPS"
L["ROLE_TANK_SHORT"]              = "T"
L["ROLE_HEAL_SHORT"]              = "H"
L["ROLE_RDPS_SHORT"]              = "R"
L["ROLE_MDPS_SHORT"]              = "M"

-- Loot
L["LOOT_RULES"]                   = "Loot Rules"
L["LOOT_SYSTEM"]                  = "Loot System"
L["LOOT_MASTER"]                  = "Master Loot"
L["LOOT_BOE_RULE"]                = "BoE Rule"
L["LOOT_BOE_RAID"]                = "BoEs to Raid"
L["LOOT_BOE_RES"]                 = "BoEs Reserved"
L["LOOT_BOE_OPEN"]                = "Open Roll"
L["LOOT_PRIMOS_RES"]              = "Primos Res"
L["LOOT_SHADOWFROST_RES"]         = "Shadowfrost Res"
L["LOOT_CRUSADER_RES"]            = "Crusader Orbs Res"
L["LOOT_RUNED_RES"]               = "Runed Orbs Res"
L["LOOT_VALANYR_RES"]             = "Val'anyr Frags Res"
L["LOOT_MSOS"]                    = "MS>OS"
L["LOOT_SK"]                      = "Suicide Kings"
L["LOOT_RANDOM"]                  = "Random"
L["LOOT_GROUP"]                   = "Group Loot"
L["LOOT_CUSTOM"]                  = "Custom"
L["LOOT_CUSTOM_RESERVES"]         = "Custom Reserves"
L["LOOT_ADVERTISE_SYSTEM"]        = "Advertise Loot System"
L["LOOT_PREVIEW"]                 = "Preview"
L["LOOT_DRAG_HINT"]               = "Drag item here or type item name"

-- Requirements
L["REQUIREMENTS"]                 = "Requirements"
L["ACTIVITY"]                     = "Activity"
L["MIN_GS"]                       = "Min GearScore"
L["FULL_GEMS"]                    = "Full Gems Required"
L["FULL_ENCHANTS"]                = "Full Enchants Required"
L["NO_PVP_GEAR"]                  = "No PvP Gear"
L["SPEC_REQUIREMENTS"]            = "Spec Requirements"
L["ADVANCED_COMP"]                = "Advanced (specific class/spec comp)"
L["CLASS"]                        = "Class"
L["SPEC"]                         = "Spec"
L["COUNT"]                        = "Count"
L["ADD"]                          = "Add"
L["COMP_LIST_EMPTY"]              = "(no class/spec requirements)"

-- Advert
L["ADVERTISEMENT"]                = "Advertisement"
L["ADVERT_SUFFIX"]                = "Suffix"
L["SEND_NOW"]                     = "Send Now"
L["AUTO_REPEAT"]                  = "Auto-Repeat"
L["INTERVAL_MIN"]                 = "Interval (min)"
L["NEXT_SEND"]                    = "Next send in: %ds"

-- Advertisement channels
L["ADVERTISE_IN"]                 = "Advertise In:"
L["CHAN_GLOBAL"]                  = "Global"
L["CHAN_TRADE"]                   = "Trade"
L["CHAN_LFG"]                     = "LFG"
L["CHAN_YELL"]                    = "Yell"
L["CHAN_SAY"]                     = "Say"
L["CHAN_GUILD"]                   = "Guild"
L["CHAN_ROTATE_HINT"]             = "When multiple channels are selected, each send rotates to the next."

-- Group / Inspection
L["GROUP_STATUS"]                 = "Group Status"
L["INSPECTING"]                   = "Inspecting %s..."
L["INSPECT_TIMEOUT"]              = "Inspect timed out for %s"
L["APPROVE"]                      = "Approve"
L["KICK"]                         = "Kick"
L["SKIP"]                         = "Skip"
L["WILL_KICK_AFTER_COMBAT"]       = "Will kick %s after combat ends."
L["MISSING_GEMS"]                 = "Missing %d gems"
L["MISSING_ENCHANTS"]             = "Missing enchants: %s"
L["PVP_GEAR_DETECTED"]            = "PvP gear detected"

-- Config
L["CONFIG"]                       = "Config"
L["WHISPER_RESPONSE"]             = "Whisper Response"
L["AUTO_INVITE_KEYWORD"]          = "Auto-invite Keyword"
L["SHOW_MINIMAP"]                 = "Show Minimap Button"
L["RESET_DEFAULTS"]               = "Reset to Defaults"
L["RESET_CONFIRM"]                = "Reset all WGB settings to defaults?"
