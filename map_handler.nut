local Prefix = "!";
local HiddenPrefix = ":"; // currently unused, not sure of a way to filter/hide chat messages
local CmdBreak = ";";

local ROOT_PERMISSION = 2;
local GIVEN_PERMISSION = 1;
local NO_PERMISSION = 0;
local Players = {}; // format: { "SteamID32": PERMISSION, etc... }
local AllowClaimRoot = true;

local INFORMATION = "\x07fbeccb";
local STATUS = "\x070080ff";
local EVENT = "\x07ffff80";
local PERMISSION = "\x07800000";
local ERROR = "\x07ff0000";

local BotSpawnDefault = true;
local AllowGiveWeapon = false;

if (AllowGiveWeapon)
    IncludeScript("give_tf_weapon/_master.nut"); // https://tf2maps.net/downloads/vscript-give_tf_weapon.14897/

local MESSAGE_MAX_LENGTH = 249;

local function min(...)
{
    local min = vargv[0];
    for (local i = 0; i < vargv.len(); i++)
    {
        if (vargv[i] < min) min = vargv[i];
    }
    return min;
}
local function max(...)
{
    local max = vargv[0];
    for (local i = 0; i < vargv.len(); i++)
    {
        if (vargv[i] > max) max = vargv[i];
    }
    return max;
}
local function clamp(value, min, max) {
    if (min > max) throw("Minimum larger than maximum");
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
local sleeps = {};
local function sleep(seconds, thr)
{
    sleeps[thr] <- Time() + seconds;
    suspend("sleep");
}

function findAll(text, pattern, from = 0, to = 0)
{
    local finds = [];
    local i = 0;
    while (i != null)
    {
        i = text.find(pattern, i);
        if (i != null)
        {
            if (from && to ? from <= i && i <= to : true)
                finds.append(i);
            i += pattern.len();
        }
    }
    return finds;
}
function findAllOutsideOf(text, pattern, start, end, from = 0, to = 0)
{
    local ignores = [];
    local finds = [];

    local i = 0;
    while (i != null)
    {
        local target = ignores.len() % 2 == 0 ? start : end;
        i = text.find(target, i);
        if (i != null)
        {
            if (from && to ? from <= i && i <= to : true)
                ignores.append(i);
            i += target.len();
        }
    }
    if (ignores.len() % 2 == 1)
        ignores.pop();

    i = 0;
    while (i != null)
    {
        i = text.find(pattern, i);
        if (i != null)
        {
            if (from && to ? from <= i && i <= to : true)
            {
                local shouldAdd = true;
                for (local j = 0; j + 1 < ignores.len(); j += 2)
                {
                    if (ignores[j] <= i && i <= ignores[j + 1])
                        shouldAdd = false;
                }
                if (shouldAdd)
                    finds.append(i);
            }
            i += pattern.len();
        }
    }
    return finds;
}
function replace(text, pattern, replacement, from = 0, to = 0)
{
    local newText = "";
    local i = 0;
    foreach (index in findAll(text, pattern, from, to))
    {
        newText += text.slice(i, index) + replacement;
        i = index + pattern.len();
    }
    newText += text.slice(i, text.len());
    return newText;
}
function splitAt(text, positions)
{
    local splits = [];
    positions.append(-1);
    positions.append(text.len());
    positions.sort();
    local lastPosition = -1;
    foreach (position in positions)
    {
        if (lastPosition == -1)
        {
            lastPosition = position + 1;
            continue;
        }

        splits.append(text.slice(lastPosition, position));
        lastPosition = position + 1;
    }
    return splits;
}
function removeStartingStr(text, char = " ")
{
    while (text.len() && text[0].tochar() == char)
        text = text.slice(1, text.len());
    return text;
}
function removeTrailingStr(text, char = " ")
{
    while (text.len() && text[text.len() - 1].tochar() == char)
        text = text.slice(0, text.len() - 1);
    return text;
}
function splitClientPrint(speaker, destination, message)
{
    while (message.len())
    {
        ClientPrint(speaker, destination, message.slice(0, min(MESSAGE_MAX_LENGTH, message.len())));
        message = message.slice(min(MESSAGE_MAX_LENGTH, message.len()), message.len());
    }
}



ClearGameEventCallbacks();



local Commands = [];
local CmdVars = {};
function AddCommand(commandInfo)
{
    if ("Variables" in commandInfo)
    {
        CmdVars[commandInfo.Command[0]] <- commandInfo.Variables;
        delete commandInfo.Variables;
    }
    if (!("Requirement" in commandInfo))
        commandInfo["Requirement"] <- 1;
    Commands.append(commandInfo);
}

local specialCases = {
    "me": function(speaker)
    {
        return [ speaker ];
    },
    "all": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
            players.append(ent);
        return players;
    },
    "others": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (speaker != ent)
                players.append(ent);
        }
        return players;
    },
    "players": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (NetProps.GetPropString(ent, "m_szNetworkIDString") != "BOT")
                players.append(ent);
        }
        return players;
    },
    "bots": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (NetProps.GetPropString(ent, "m_szNetworkIDString") == "BOT")
                players.append(ent);
        }
        return players;
    },
    "blu": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (ent.GetTeam() == 3)
                players.append(ent);
        }
        return players;
    },
    "red": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (ent.GetTeam() == 2)
                players.append(ent);
        }
        return players;
    },
    "team": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (speaker.GetTeam() == ent.GetTeam())
                players.append(ent);
        }
        return players;
    },
    "enemies": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (speaker.GetTeam() != ent.GetTeam())
                players.append(ent);
        }
        return players;
    },
    "#_": function(speaker, text)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
            players.append(ent);
        local selection = [];
        for (local i = 1; i <= text.tointeger(); i++)
            selection.append(players[RandomInt(0, players.len() - 1)]);
        return selection;
    },
    "*_": function(speaker, text)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (speaker != ent)
                players.append(ent);
        }
        local selection = [];
        for (local i = 1; i <= text.tointeger(); i++)
            selection.append(players[RandomInt(0, players.len() - 1)]);
        return selection;
    },
    "<_": function(speaker, text)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (speaker != ent && (speaker.GetOrigin() - ent.GetOrigin()).Length() < text.tofloat() && ent.IsAlive())
                players.append(ent);
        }
        return players;
    },
    "id=_": function(speaker, text)
    {
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (NetProps.GetPropString(ent, "m_szNetworkIDString") == text.toupper())
                return [ ent ];
        }
        return [];
    },
    "!picker": function(speaker)
    {
        local start = speaker.EyePosition();
        local dir = speaker.EyeAngles().Forward();
        local end = start + dir * 32768;

        local trace = {
            "start": start,
            "end": end,
            "ignore": speaker,
            "mask": (0x1 | 0x4000 | 0x2000000 | 0x2 | 0x4000000 | 0x40000000 | 0x8) //MASK_SHOT | CONTENTS_GRATE
        };
        if (!TraceLineEx(trace)) throw("Trace error. ");

        if (trace.hit)
            return [ trace.enthit ];
        return [];
    }
}
specialCases["blue"] <- specialCases["blu"];
specialCases["uid=_"] <- specialCases["id=_"];

function GetPlayers(speaker, text)
{
    local list = split(text.tolower(), ",");
    local add = [], sub = [];

    foreach (plrStr in list)
    {
        local to = add;
        if (plrStr.find("+") == 0)
            plrStr = replace(plrStr, "+", "");
        else if (plrStr.find("-") == 0)
            to = sub; plrStr = replace(plrStr, "-", "");

        local caseFound = false;
        foreach (str,func in specialCases)
        {
            if (str.find("_") != null && plrStr.find(replace(str, "_", "")) == 0)
            {
                try
                {
                    foreach (player in func(speaker, plrStr.slice(replace(str, "_", "").len(), plrStr.len())))
                    {
                        if (to.find(player) == null) to.append(player);
                    }
                    caseFound = true
                }
                catch (err) {}
            }
            if (plrStr == str && !caseFound)
            {
                caseFound = true;
                foreach (player in func(speaker))
                {
                    if (to.find(player) == null) to.append(player);
                }
            }
        }
        if (!caseFound)
        {
            local ent; while (ent = Entities.FindByClassname(ent, "player"))
            {
                if (NetProps.GetPropString(ent, "m_szNetname").tolower().find(plrStr) == 0 && to.find(ent) == null)
                    to.append(ent);
            }
        }
    }

    local players = [];
    foreach (player in add)
    {
        if (sub.find(player) == null)
        {
            players.append(player);
        }
    }
    return players;
}
function GetPlayerPermission(player, fallback = NO_PERMISSION)
{
    local uID = NetProps.GetPropString(player, "m_szNetworkIDString");
    if (uID == "")
        return ROOT_PERMISSION; // grant console root permission

    local foundRoot = false;
    foreach (uID,permission in Players)
    {
        if (permission == ROOT_PERMISSION)
            foundRoot = true;
    }
    if (!foundRoot)
        return GIVEN_PERMISSION;

    if (uID in Players)
        return Players[uID];

    return fallback;
}

AddCommand({
    "Command": [ "commands", "cmds", "help" ], // base command and aliases
    "Arguments": [ { "command": "__generic" } ], // arguments; { "Argument": Default }; if default is null, argument will be asserted (dictionaries within lists as order is otherwise not maintained)
    "Description": [ "Displays command info, or information about a specific command", "Player arguments:", "  '<name>' - starting with <name>, not case sensitive", "  'me' - you.", "  'all' - all players", "  'others' - other players", "  'players' - real players", "  'bots' - buckets of bolts", "  'blu' - players on BLU", "  'red' - players on RED" ],
        // ^ command info; any information after the first index will be treated as extra info only given with '!help <cmd>' (be sure any text does not exceed 255 bytes in order to be shown)
    "Function": function(speaker, args, vars = null) // function executed when command is used; player who used command, any arguments used, and associated variables are passed
    {
        splitClientPrint(speaker, 3, INFORMATION + "  Information printed in console");
        if (args[0] == "__generic")
        {
            splitClientPrint(speaker, 1, "\nCommands: \n\n");
            foreach (entry in Commands)
            {
                local text = format("  %s%s", Prefix, entry.Command[0]);
                foreach (dict in entry.Arguments)
                {
                    local arg, def; foreach (i,v in dict) { arg = i; def = v }
                    if (def == null)
                        text += format(" [%s]", arg);
                    else
                        text += format(" (%s)", arg);
                }
                text += format(" - requirement: %d", entry.Requirement);
                text += format("\n    >%s\n\n", entry.Description[0]);
                splitClientPrint(speaker, 1, text);
            }
            splitClientPrint(speaker, 1, format("  Use '%shelp <command>' to see more information about a command", Prefix));
        }
        else
        {
            local entry;
            foreach (command in Commands)
            {
                foreach (_,alias in command.Command)
                {
                    if (args[0] == alias)
                        entry = command;
                }
            }
            if (entry != null)
            {
                splitClientPrint(speaker, 1, format("\n  %s: \n", entry.Command[0]));
                splitClientPrint(speaker, 1, format("    >requirement: %d\n", entry.Requirement));
                local text = "    >aliases: ";
                foreach (index,alias in entry.Command)
                {
                    if (index != 0)
                        text += " / ";
                    text += alias;
                }
                text += "\n    >arguments:";
                foreach (dict in entry.Arguments)
                {
                    local arg, def; foreach (i,v in dict) { arg = i; def = v }
                    if (def == null)
                        text += format(" [%s]", arg);
                    else
                        text += format(" (%s: %s)", arg, def);
                }
                text += "\n    >" + entry.Description[0];
                splitClientPrint(speaker, 1, text);

                if (entry.Description.len() > 1)
                {
                    foreach (index, text in entry.Description)
                    {
                        if (index != 0)
                            splitClientPrint(speaker, 1, format("     %s", text));
                    }
                }
                else
                    splitClientPrint(speaker, 1, "     No extra information given");
                splitClientPrint(speaker, 1, "\n");
            }
            else
                splitClientPrint(speaker, 1, "\nNo such command exists");
        }
    }
    //"Variables": { "Variable": value } // associated variables with the command
    //"Requirement": 1 // permission needed to run command, defaulted to 1
});
AddCommand({
    "Command": [ "getsteamid", "steamid", "getid", "id", "getname", "name" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Gets a player's Steam ID" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            splitClientPrint(speaker, 3, INFORMATION + format("  %s: %s", NetProps.GetPropString(player, "m_szNetname"), NetProps.GetPropString(player, "m_szNetworkIDString")));
    }
});
if (AllowClaimRoot)
{
    AddCommand({
        "Command": [ "claimroot" ],
        "Arguments": [],
        "Description": [ "If no players have permissions, claim root" ],
        "Function": function(speaker, args, vars = null)
        {
            if (!Players.len())
            {
                Players[NetProps.GetPropString(speaker, "m_szNetworkIDString")] <- ROOT_PERMISSION;
                splitClientPrint(speaker, 3, PERMISSION + "  Claimed root");
            }
            else
                splitClientPrint(speaker, 3, PERMISSION + "  Can't claim root");
        }
    });
}
AddCommand({
    "Command": [ "whitelist" ],
    "Arguments": [ { "player": null } ],
    "Description": [ "Gives command permissions to players" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local uID = NetProps.GetPropString(player, "m_szNetworkIDString");
            if (!(uID in Players) || Players[uID] == NO_PERMISSION)
            {
                Players[uID] <- GIVEN_PERMISSION;
                splitClientPrint(speaker, 3, PERMISSION + format("  Gave command permissions to %s", NetProps.GetPropString(player, "m_szNetname")));
            }
        }
    },
    "Requirement": 2
});
AddCommand({
    "Command": [ "unwhitelist" ],
    "Arguments": [ { "player": null } ],
    "Description": [ "Removes command permissions to players" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local uID = NetProps.GetPropString(player, "m_szNetworkIDString");
            if (uID in Players && GetPlayerPermission(player) < ROOT_PERMISSION)
            {
                delete Players[uID];
                splitClientPrint(speaker, 3, PERMISSION + format("  Removed command permissions from %s", NetProps.GetPropString(player, "m_szNetname")));
            }
        }
    },
    "Requirement": 2
});
AddCommand({
    "Command": [ "permissions", "permission" ],
    "Arguments": [ { "player": null } ],
    "Description": [ "Gets command permissions of players" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            splitClientPrint(speaker, 3, PERMISSION + format("  Permission of %s is %d", NetProps.GetPropString(player, "m_szNetname"), GetPlayerPermission(player)));
    }
});
AddCommand({
    "Command": [ "respawn" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Respawn a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.ForceRespawn();
    }
});
AddCommand({
    "Command": [ "refresh" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Respawn a player, while retaining position, viewangles, and some other information" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local origin = player.GetOrigin();
            local velocity = player.GetVelocity();
            local angles = player.EyeAngles();
            local moveType = player.GetMoveType();
            player.ForceRespawn();
            player.SetAbsOrigin(origin);
            player.SetVelocity(velocity);
            player.SnapEyeAngles(angles);
            player.SetMoveType(moveType, 0);
        }
    }
});
AddCommand({
    "Command": [ "stun" ],
    "Arguments": [ { "player": "me" }, { "duration": "1" }, { "speed reduction": "0.5" }, { "flags": "1" } ],
    "Description": [ "Stuns a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.StunPlayer(args[1].tofloat(), args[2].tofloat(), args[3].tointeger(), null);
    }
});
AddCommand({
    "Command": [ "kill" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Kill a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            //NetProps.SetPropInt(player, "m_lifeState", 1);
            player.TakeDamage(player.GetHealth() + 1, 0, null);
        }
    }
});
AddCommand({
    "Command": [ "kick" ],
    "Arguments": [ { "player": null } ],
    "Description": [ "Kicks a player", "This is hacky, partially kicks players, and may fuck with games. Don't use on people you like :)" ],
    "Function": function(speaker, args, vars = null)
    {
        local speakerPermission = GetPlayerPermission(speaker);
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local playerPermission = GetPlayerPermission(player);
            if (speakerPermission <= playerPermission)
            {
                splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to kick %s", NetProps.GetPropString(player, "m_szNetname")));
                continue;
            }

            splitClientPrint(speaker, 3, EVENT + format("  Kicked %s", NetProps.GetPropString(player, "m_szNetname")));
            player.Kill(); // is there a better way to kick/remove players?
        }
    }
});
local Bans = {};
AddCommand({
    "Command": [ "ban" ],
    "Arguments": [ { "player": null } ],
    "Description": [ "Bans a player", "This is hacky, partially kicks players, and may fuck with games. Don't use on people you like :)" ],
    "Function": function(speaker, args, vars = null)
    {
        local speakerPermission = GetPlayerPermission(speaker);
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local playerPermission = GetPlayerPermission(player);
            if (speakerPermission <= playerPermission)
            {
                splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to ban %s", NetProps.GetPropString(player, "m_szNetname")));
                continue;
            }

            Bans[NetProps.GetPropString(player, "m_szNetworkIDString")] <- { "Name": NetProps.GetPropString(player, "m_szNetname"), "Requirement": speakerPermission };
            splitClientPrint(speaker, 3, EVENT + format("  Banned %s", NetProps.GetPropString(player, "m_szNetname")));
            player.Kill();
        }
    }
});
AddCommand({
    "Command": [ "unban" ],
    "Arguments": [ { "player": null } ],
    "Description": [ "Unbans a player" ],
    "Function": function(speaker, args, vars = null)
    {
        local speakerPermission = GetPlayerPermission(speaker);
        foreach (uID,info in Bans)
        {
            if (speakerPermission < info.Requirement)
            {
                splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to unban %s", info.Name));
                continue;
            }

            if (uID.tolower() == args[0].tolower() || info.Name.tolower() == args[0].tolower() || args[0].tolower() == "all")
            {
                splitClientPrint(speaker, 3, EVENT + format("  Unbanned %s", info.Name));
                delete Bans[uID];
            }
        }
    }
});
AddCommand({
    "Command": [ "getbans", "bans" ],
    "Arguments": [],
    "Description": [ "Gets ban list" ],
    "Function": function(speaker, args, vars = null)
    {
        splitClientPrint(speaker, 3, STATUS + "  Bans:");
        foreach (uID,info in Bans)
            splitClientPrint(speaker, 3, STATUS + format("    %s (%s) -> %d", info.Name, uID, info.Requirement));
    }
});
AddCommand({
    "Command": [ "chat" ],
    "Arguments": [ { "player": null }, { "message": null } ],
    "Description": [ "Force a player to chat" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            Say(player, format("\x02%s", args[1]), false); // use \x02 to prevent unwanted usage of commands
    }
});
AddCommand({
    "Command": [ "team_chat", "teamchat" ],
    "Arguments": [ { "player": null, "message": null } ],
    "Description": [ "Force a player to team chat" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            Say(player, format("\x02%s", args[1]), true);
    }
});
AddCommand({
    "Command": [ "gravity", "grav" ],
    "Arguments": [ { "value": "800" } ],
    "Description": [ "Sets the gravity of the server" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("sv_gravity", args[0].tofloat());
    }
});
AddCommand({
    "Command": [ "speed" ],
    "Arguments": [ { "player": "me" }, { "speed": "300" } ],
    "Description": [ "Change a player's walking speed", "Note: annoyingly capped at 520, prone to being overwritten" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            NetProps.SetPropFloat(player, "m_flMaxspeed", args[1].tofloat());
    }
});
AddCommand({
    "Command": [ "friendlyfire", "friendly" ],
    "Arguments": [],
    "Description": [ "Toggles whether friendly fire is enabled" ],
    "Function": function(speaker, args, vars = null)
    {
        if (Convars.GetInt("mp_friendlyfire") == 0)
            Convars.SetValue("mp_friendlyfire", 1);
        else
            Convars.SetValue("mp_friendlyfire", 0);
    }
});
AddCommand({
    "Command": [ "heal" ],
    "Arguments": [ { "player": "me" }, { "override": "false" } ],
    "Description": [ "Heals players back to full health" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            if (args[1].tolower() == "t" || args[1].tolower() == "true")
                player.SetHealth(player.GetMaxHealth());
            else
                player.SetHealth(max(player.GetMaxHealth(), player.GetHealth()));
        }
    }
});
AddCommand({
    "Command": [ "health" ],
    "Arguments": [ { "player": "me" }, { "value": null } ],
    "Description": [ "Gives all players a given health" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.SetHealth(args[1].tointeger());
    }
});
if (AllowGiveWeapon)
{
    AddCommand({
        "Command": ["give_weapon", "giveweapon", "give"],
        "Arguments": [ { "player": "me" }, { "weapon": null } ],
        "Description": [""],
        "Function": function(speaker, args, vars = null) {
            foreach (player in GetPlayers(speaker, args[0])) {
                player.GiveWeapon(args[1])
            }
        }
    });
}
AddCommand({
    "Command": [ "noclip" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Toggles a player's noclip" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            if (player.GetMoveType() != 8)
                player.SetMoveType(8, 0);
            else
                player.SetMoveType(2, 0);
        }
    }
});
AddCommand({
    "Command": [ "setmovetype", "movetype" ],
    "Arguments": [ { "player": "me" }, { "movetype": "2" }, { "movecollide": "0" } ],
    "Description": [ "Sets a player's movetype", "See https://developer.valvesoftware.com/wiki/Team_Fortress_2/Scripting/Script_Functions/Constants for values for EMoveType and EMoveCollide" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.SetMoveType(args[1].tointeger(), args[2].tointeger());
    }
});
AddCommand({
    "Command": [ "teleport", "tp" ],
    "Arguments": [ { "from": "me" }, { "to": "me" }, { "offset": "false" } ],
    "Description": [ "Teleports players to another player", "from: '<player>'", "to: '<player>', '__cursor' / '__bounds' / '__plane' / '__point' - your aim position, with varying bounds (__plane and __point may get stuck), 'vector(x, y, z)' - some position" ],
    "Function": function(speaker, args, vars = null)
    {
        local pos = Vector(), offset = Vector();

        switch (args[1])
        {
        case "__cursor":
            local start = speaker.EyePosition();
            local dir = speaker.EyeAngles().Forward();
            local end = start + dir * 32768;

            local mins = Vector(-24, -24, 0), maxs = Vector(24, 24, 82);

            local trace = {
                "start": start,
                "end": end,
                "ignore": speaker,
                "hullmin": mins,
                "hullmax": maxs,
                "mask": (0x1 | 0x4000 | 0x10000 | 0x2 | 0x2000000 | 0x8) //MASK_PLAYERSOLID
            };
            if (!TraceHull(trace)) throw("Trace error. ");

            pos = trace.pos;
            break;
        case "__bounds":
            local diff = Vector(0, 0, speaker.EyePosition().z - speaker.GetOrigin().z);

            local start = speaker.EyePosition();
            local dir = speaker.EyeAngles().Forward();
            local end = start + dir * 32768;

            local mins = Vector(-24, -24, 0) - diff, maxs = Vector(24, 24, 82) - diff;

            local trace = {
                "start": start,
                "end": end,
                "ignore": speaker,
                "hullmin": mins,
                "hullmax": maxs,
                "mask": (0x1 | 0x4000 | 0x10000 | 0x2 | 0x2000000 | 0x8) //MASK_PLAYERSOLID
            };
            if (!TraceHull(trace)) throw("Trace error. ");

            pos = trace.pos - diff;
            break;
        case "__plane":
            local start = speaker.EyePosition();
            local dir = speaker.EyeAngles().Forward();
            local end = start + dir * 32768;

            local mins = Vector(-24, -24, 0), maxs = Vector(24, 24, 0);

            local trace = {
                "start": start,
                "end": end,
                "ignore": speaker,
                "hullmin": mins,
                "hullmax": maxs,
                "mask": (0x1 | 0x4000 | 0x10000 | 0x2 | 0x2000000 | 0x8) //MASK_PLAYERSOLID
            };
            if (!TraceHull(trace)) throw("Trace error. ");

            pos = trace.pos;
            break;
        case "__point":
            local start = speaker.EyePosition();
            local dir = speaker.EyeAngles().Forward();
            local end = start + dir * 32768;

            local trace = {
                "start": start,
                "end": end,
                "ignore": speaker,
                "mask": (0x1 | 0x4000 | 0x10000 | 0x2 | 0x2000000 | 0x8) //MASK_PLAYERSOLID
            };
            if (!TraceLineEx(trace)) throw("Trace error. ");

            pos = trace.pos;
            break;
        default:
            try
            {
                local text = replace(args[1] + (args[2] != "false" ? args[2] : ""), " ", "");
                text = replace(text, "vector(", "("); text = replace(text, "v(", "(");
                if (!(text.len() && text[0].tochar() == "(" || text[text.len() - 1].tochar() == ")"))
                    throw("");
                text = text.slice(1, text.len() - 1);
                local vector = split(text, ",");
                if (vector.len() != 3)
                    throw("");

                pos = Vector(vector[0].tofloat(), vector[1].tofloat(), vector[2].tofloat());
            }
            catch (err)
            {
                local player = GetPlayers(speaker, args[1])[0];
                pos = player.GetOrigin();
                if (args[2].tolower() == "t" || args[2].tolower() == "true")
                    offset += Vector(0, 0, player.GetBoundingMaxs().z + 1);
            }
        }

        foreach (player in GetPlayers(speaker, args[0]))
        {
            player.SetAbsOrigin(pos + offset);
            if (args[2].tolower() == "t" || args[2].tolower() == "true")
                offset += Vector(0, 0, player.GetBoundingMaxs().z + 1);
        }
    }
});
AddCommand({
    "Command": [ "getposition", "getpos", "gp" ],
    "Arguments": [ { "player": "me" }, { "precise": "false" } ],
    "Description": [ "Gets the position of a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local vec = player.GetOrigin();
            if (args[1].tolower() == "t" || args[1].tolower() == "true")
                splitClientPrint(speaker, 3, STATUS + format("  Position of %s is vector(%.9g, %.9g, %.9g)", NetProps.GetPropString(player, "m_szNetname"), vec.x, vec.y, vec.z));
            else
                splitClientPrint(speaker, 3, STATUS + format("  Position of %s is vector(%.0f, %.0f, %.0f)", NetProps.GetPropString(player, "m_szNetname"), vec.x, vec.y, vec.z));
        }
    }
});
AddCommand({
    "Command": [ "setvelocity", "setvel", "sv" ],
    "Arguments": [ { "player": "me" }, { "velocity": null } ],
    "Description": [ "Sets the velocity of a player", "velocity: 'vector(x, y, z)'" ],
    "Function": function(speaker, args, vars = null)
    {
        local text = replace(args[1], " ", "");
        text = replace(text, "vector(", "("); text = replace(text, "v(", "(");
        if (!(text.len() && text[0].tochar() == "(" || text[text.len() - 1].tochar() == ")"))
            return;
        text = text.slice(1, text.len() - 1);
        local vector = split(text, ",");
        if (vector.len() != 3)
            return;

        local value = Vector(vector[0].tofloat(), vector[1].tofloat(), vector[2].tofloat());
        foreach (player in GetPlayers(speaker, args[0]))
            player.SetVelocity(value);
    }
});
AddCommand({
    "Command": [ "getvelocity", "getvel", "gv" ],
    "Arguments": [ { "player": "me" }, { "precise": "false" } ],
    "Description": [ "Gets the velocity of a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local vec = player.GetVelocity();
            if (args[1].tolower() == "t" || args[1].tolower() == "true")
                splitClientPrint(speaker, 3, STATUS + format("  Velocity of %s is vector(%.9g, %.9g, %.9g)", NetProps.GetPropString(player, "m_szNetname"), vec.x, vec.y, vec.z));
            else
                splitClientPrint(speaker, 3, STATUS + format("  Velocity of %s is vector(%.0f, %.0f, %.0f)", NetProps.GetPropString(player, "m_szNetname"), vec.x, vec.y, vec.z));
        }
    }
});
AddCommand({
    "Command": [ "setangles", "setang", "sa" ],
    "Arguments": [ { "player": "me" }, { "angles": null } ],
    "Description": [ "Sets the eye angles of a player", "angles: 'vector(x, y, z)'" ],
    "Function": function(speaker, args, vars = null)
    {
        local text = replace(args[1], " ", "");
        text = replace(text, "vector(", "("); text = replace(text, "v(", "(");
        text = replace(text, "qangle(", "("); text = replace(text, "q(", "(");
        if (!(text.len() && text[0].tochar() == "(" || text[text.len() - 1].tochar() == ")"))
            return;
        text = text.slice(1, text.len() - 1);
        local vector = split(text, ",");
        if (vector.len() != 3)
            return;

        local value = QAngle(vector[0].tofloat(), vector[1].tofloat(), vector[2].tofloat());
        foreach (player in GetPlayers(speaker, args[0]))
            player.SnapEyeAngles(value);
    }
});
AddCommand({
    "Command": [ "getangles", "getang", "ga" ],
    "Arguments": [ { "player": "me" }, { "precise": "false" } ],
    "Description": [ "Gets the eye angles of a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local ang = player.EyeAngles();
            if (args[1].tolower() == "t" || args[1].tolower() == "true")
                splitClientPrint(speaker, 3, STATUS + format("  Eye angles of %s is qangle(%.9g, %.9g, %.9g)", NetProps.GetPropString(player, "m_szNetname"), ang.x, ang.y, ang.z));
            else
                splitClientPrint(speaker, 3, STATUS + format("  Eye angles of %s is qangle(%.0f, %.0f, %.0f)", NetProps.GetPropString(player, "m_szNetname"), ang.x, ang.y, ang.z));
        }
    }
});
AddCommand({
    "Command": [ "thirdperson", "third" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Forces third person" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.SetForcedTauntCam(1);
    }
});
AddCommand({
    "Command": [ "firstperson", "first" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Forces first person" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.SetForcedTauntCam(0);
    }
})
AddCommand({
    "Command": [ "taunt" ],
    "Arguments": [ { "player": "me" },{ "taunt": null } ],
    "Description": [ "Forces a player to taunt", "Taunt IDs: https://github.com/Bradasparky/tf_taunt_tastic/blob/main/addons/sourcemod/configs/tf_taunt_tastic.cfg" /*, "Taunt IDs: https://wiki.alliedmods.net/Team_fortress_2_item_definition_indexes#Taunt_Items", "Taunt IDs: https://steamcommunity.com/app/440/discussions/0/2765630416816834092/"*/ ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local weapon = Entities.CreateByClassname("tf_weapon_bat");
            local activeWeapon = player.GetActiveWeapon();
            
            player.StopTaunt(true) // both are needed to fully clear the taunt
            player.RemoveCond(7)
            
            weapon.DispatchSpawn()
            NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", args[1].tointeger())
            NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true)
            NetProps.SetPropBool(weapon, "m_bForcePurgeFixedupStrings", true)
            NetProps.SetPropEntity(player, "m_hActiveWeapon", weapon)
            NetProps.SetPropInt(player, "m_iFOV", 0) // fix sniper rifles
            player.HandleTauntCommand(0)
            NetProps.SetPropEntity(player, "m_hActiveWeapon", activeWeapon)
            weapon.Kill()
        }
    }
});
AddCommand({
    "Command": [ "fov" ],
    "Arguments": [ { "player": "me" }, { "value": 90 } ],
    "Description": [ "Forces first person" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            NetProps.SetPropInt(player, "m_iFOV", args[1].tointeger());
    }
});
AddCommand({
    "Command": [ "team" ],
    "Arguments": [ { "player": "me" }, { "team": "__swap" }, { "respawn": "false" } ],
    "Description": [ "Sets a player's team", "Team: Numbers or 'BLU' / 'RED'; '2' - RED, '3' - BLU" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local newTeam = 0;
            if (args[1] == "__swap")
            {
                switch (player.GetTeam())
                {
                case 2: newTeam = 3; break;
                case 3: newTeam = 2; break;
                }
            }
            else if (args[1].tolower() == "blu" || args[1].tolower() == "blue")
                newTeam = 3;
            else if (args[1].tolower() == "red")
                newTeam = 2;
            else
                newTeam = args[1].tointeger();
            newTeam = clamp(newTeam, 0, 3); // avoid crashes (hopefully)

            player.ForceChangeTeam(newTeam, true);
            NetProps.SetPropInt(player, "m_iTeamNum", newTeam);
            local cosmetic = null; while (cosmetic = Entities.FindByClassname(cosmetic, "tf_wearable"))
            {
                if (cosmetic.GetOwner() == player)
                    cosmetic.SetTeam(newTeam);
            }

            if (args[2].tolower() == "t" || args[2].tolower() == "true")
                player.ForceRespawn();
        }
    }
});
AddCommand({
    "Command": [ "class" ],
    "Arguments": [ { "player": "me" }, { "team": "random" }, { "mode": "refresh" } ],
    "Description": [ "Sets a player's class" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local classId = 0;
            try
            {
                classId = args[1].tointeger();
            }
            catch (err) {}
            switch (args[1].tolower())
            {
            case "scout": classId = 1; break;
            case "soldier": classId = 3; break;
            case "pyro": classId = 7; break;
            case "demo":
            case "demoman": classId = 4; break;
            case "heavy": classId = 6; break;
            case "engi":
            case "engineer": classId = 9; break;
            case "medic": classId = 5; break;
            case "sniper": classId = 2; break;
            case "spy": classId = 8; break;
            }
            if (!classId)
                classId = RandomInt(1, 9);
            
            player.SetPlayerClass(classId);
            NetProps.SetPropInt(player, "m_Shared.m_iDesiredPlayerClass", classId);

            switch (args[2].tolower())
            {
            case "respawn":
                player.ForceRespawn();
                break;
            case "refresh":
                local origin = player.GetOrigin();
                local velocity = player.GetVelocity();
                local angles = player.EyeAngles();
                local moveType = player.GetMoveType();
                player.ForceRespawn();
                player.SetAbsOrigin(origin);
                player.SetVelocity(velocity);
                player.SnapEyeAngles(angles);
                player.SetMoveType(moveType, 0);
            }
        }
    }
});
AddCommand({
    "Command": [ "mp_waitingforplayers_cancel", "nowarmup" ],
    "Arguments": [ { "int": "1" } ],
    "Description": [ "Sets mp_waitingforplayers_cancel" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("mp_waitingforplayers_cancel", args[0].tofloat());
    }
});
AddCommand({
    "Command": [ "settime" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets time for any team round timers" ],
    "Function": function(speaker, args, vars = null)
    {
        for (local ent; ent = Entities.FindByClassname(ent, "team_round_timer");)
            ent.AcceptInput("settime", args[0], null, null);
    }
});
AddCommand({
    "Command": [ "addtime" ],
    "Arguments": [ { "int": null} ],
    "Description": [ "Adds time to any team round timers" ],
    "Function": function(speaker, args, vars = null)
    {
        for (local ent; ent = Entities.FindByClassname(ent, "team_round_timer");)
            ent.AcceptInput("addtime", args[0], null, null);
    }
});
AddCommand({
    "Command": [ "setmaxtime" ],
    "Arguments": [ { "int": null } ],
    "Description": [ "Sets max time for any team round timers" ],
    "Function": function(speaker, args, vars = null)
    {
        for (local ent; ent = Entities.FindByClassname(ent, "team_round_timer");)
            ent.AcceptInput("setmaxtime", args[0], null, null);
    }
});
AddCommand({
    "Command": [ "toggletime" ],
    "Arguments": [ { "int": "__toggle" } ],
    "Description": [ "Sets mp_waitingforplayers_cancel" ],
    "Function": function(speaker, args, vars = null)
    {
        for (local ent; ent = Entities.FindByClassname(ent, "team_round_timer");)
        {
            local bValue;
            if (args[0] == "__toggle")
                bValue = !NetProps.GetPropBool(ent, "m_bTimerPaused");
            else
                bValue = args[0].tolower() == "t" || args[0].tolower() == "true" ? true : false;
            ent.AcceptInput(bValue ? "disable" : "enable", "", null, null);
        }
    }
});
AddCommand({
    "Command": [ "instant_respawn", "instantrespawn", "instant" ],
    "Arguments": [],
    "Description": [ "Toggles instant respawning" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Instant respawn enabled");
        else
            splitClientPrint(speaker, 3, EVENT + "  Instant respawn disabled");
    },
    "Variables": { "Enabled": true }
});
local customSpawns = {}
AddCommand({
    "Command": [ "custom_spawn", "customspawn", "set_spawn", "setspawn" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Creates a custom respawn point for a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local pos = player.GetOrigin() + Vector(0, 0, 1);
            local ang = player.EyeAngles();
            customSpawns[player] <- [ pos, ang ];
            splitClientPrint(speaker, 3, EVENT + format("  Gave %s a custom spawn at vector(%.9g, %.9g, %.9g)", NetProps.GetPropString(player, "m_szNetname"), pos.x, pos.y, pos.z));
        }
    }
});
AddCommand({
    "Command": [ "remove_custom_spawn", "removecustomspawn", "reset_spawn", "resetspawn" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Removes a custom respawn point for a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            if (player in customSpawns) delete customSpawns[player];
            splitClientPrint(speaker, 3, EVENT + format("  Removed %s's custom spawn"), NetProps.GetPropString(player, "m_szNetname"));
        }
    }
});
AddCommand({
    "Command": [ "constant_regen", "constantregen", "constant", "regen" ],
    "Arguments": [],
    "Description": [ "Toggles constant refresh of health and ammo" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Constant regen enabled");
        else
            splitClientPrint(speaker, 3, EVENT + "  Constant regen disabled");
    },
    "Variables": { "Enabled": true }
});
AddCommand({
    "Command": [ "health_regen", "regen_health" ],
    "Arguments": [],
    "Description": [ "Toggles constant refresh of health in regen" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Health regen enabled");
        else
            splitClientPrint(speaker, 3, EVENT + "  Health regen disabled");
    },
    "Variables": { "Enabled": true }
});
AddCommand({
    "Command": [ "ammo_regen", "regen_ammo" ],
    "Arguments": [],
    "Description": [ "Toggles constant refresh of ammo in regen" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Ammo regen enabled");
        else
            splitClientPrint(speaker, 3, EVENT + "  Ammo regen disabled");
    },
    "Variables": { "Enabled": true }
});
AddCommand({
    "Command": [ "item_regen", "regen_item" ],
    "Arguments": [],
    "Description": [ "Toggles constant refresh of items in regen" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Item regen enabled");
        else
            splitClientPrint(speaker, 3, EVENT + "  Item regen disabled");
    },
    "Variables": { "Enabled": true }
});
AddCommand({
    "Command": [ "regen_permission", "regen_requirement" ],
    "Arguments": [ { "permission": null } ],
    "Description": [ "Sets permission required to have regen be used" ],
    "Function": function(speaker, args, vars = null)
    {
        local permission = args[0].tointeger();
        local speakerPermission = GetPlayerPermission(speaker);
        if (speakerPermission < vars.Requirement || speakerPermission < permission)
        {
            splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to set regen permission from %d to %d", vars.Requirement, permission));
            return;
        }

        vars.Requirement = permission;
        splitClientPrint(speaker, 3, EVENT + format("  Regen permission set to %d", permission));
    },
    "Variables": { "Requirement": NO_PERMISSION }
});
AddCommand({
    "Command": [ "grappling_hook", "grapple" ],
    "Arguments": [],
    "Description": [ "Toggles grappling hook" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("tf_grapplinghook_enable", !Convars.GetBool("tf_grapplinghook_enable"));
    }
});
AddCommand({
    "Command": [ "impulse" ],
    "Arguments": [ { "range": "1000" }, { "power": "1000" }, { "dropoff": "0" }, { "players": "others" } ],
    "Description": [ "Applies an impulse at the cursor akin to a rocket launcher", "dropoff: the amount the power drops off, in %, to the edge of range" ],
    "Function": function(speaker, args, vars = null)
    {
        local start = speaker.EyePosition();
        local dir = speaker.EyeAngles().Forward();
        local end = start + dir * 32768;

        local trace = {
            "start": start,
            "end": end,
            "ignore": speaker
        };
        if (!TraceLineEx(trace)) throw("TraceLineEx error. ");

        foreach (player in GetPlayers(speaker, args[3]))
        {
            local dist = (player.GetOrigin() + Vector(0, 0, 42) - trace.pos).Length();
            if (dist > args[0].tofloat()) continue;

            local _trace = {
                "start": trace.pos,
                "end": player.GetOrigin() + Vector(0, 0, 42),
                "ignore": player
            };
            if (!TraceLineEx(_trace)) throw("TraceLineEx error. ");
            if (_trace.hit) continue;

            local _dir = (player.GetOrigin() + Vector(0, 0, 42) - trace.pos); dist /= args[0].tofloat(); _dir.Norm();
            printl(_dir * (1 - (dist * args[2].tofloat())) * args[1].tofloat());
            player.SetAbsOrigin(player.GetOrigin() + Vector(0, 0, 19));
            player.ApplyAbsVelocityImpulse(_dir * (1 - (dist * args[2].tofloat())) * args[1].tofloat());
        }
    }
});
local TimedAttributes = [];
AddCommand({
    "Command": [ "attribute", "atr" ],
    "Arguments": [ { "player": "me" }, { "slot": "self" }, { "attribute": null }, { "value": "__get" }, { "duration": "infinite" } ],
    "Description": [ "Gives the player/weapon a custom attribute", "slot: 'self' - applied to you, '0' - primary, '1' - secondary, '2' - tertiary, etc (conditions can only be applied to player)", "attribute: '<string>' - list at https://wiki.teamfortress.com/wiki/List_of_item_attributes" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local ent;
            if (args[1] == "self")
            {
                ent = player;
                if (args[3] != "__get")
                    ent.AddCustomAttribute(args[2], args[3].tofloat(), -1);
                else
                    splitClientPrint(speaker, 3, STATUS + format("  Attribute %s is %.9g", args[2], ent.GetCustomAttribute(args[2], -2147483647)));
            }
            else
            {
                ent = NetProps.GetPropEntityArray(player, "m_hMyWeapons", args[1].tointeger());
                if (args[3] != "__get")
                    ent.AddAttribute(args[2], args[3].tofloat(), -1);
                else
                    splitClientPrint(speaker, 3, STATUS + format("  Attribute %s is %.9g", args[2], ent.GetAttribute(args[2], -2147483647)));
            }
            if (args[4] != "infinite" && ent != null)
            {
                TimedAttributes.append({
                    "Ent": ent
                    "Attribute": dict.AtrCond,
                    "Time": Time(),
                    "Duration": dict.Duration.tofloat()
                });
            }
        }
    }
});
AddCommand({
    "Command": [ "condition", "cond" ],
    "Arguments": [ { "player": "me" }, { "condition": null }, { "duration": "infinite" } ],
    "Description": [ "Gives the player/weapon a custom attribute", "condition: '<id>' - list at https://wiki.teamfortress.com/wiki/Cheats#addcond" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            if (args[2] == "infinite")
                player.AddCond(args[1].tointeger())
            else
                player.AddCondEx(args[1].tointeger(), args[2].tofloat(), player)
        }
    }
});
AddCommand({
    "Command": [ "netvar", "netprop", "net" ],
    "Arguments": [ { "player": "me" }, { "slot": "self" }, { "netvar": null }, { "value": "__get" } ],
    "Description": [ "Sets or gets the netvar of the player/weapon", "slot: 'self' - applied to you, '0' - primary, '1' - secondary, '2' - tertiary, etc", "netprop: '<string>' - list at https://jackz.me/netprops/tf2/netprops / https://sigwiki.potato.tf/index.php/Entity_Properties" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local ent;
            if (args[1] == "self")
                ent = player;
            else
                ent = NetProps.GetPropEntityArray(player, "m_hMyWeapons", args[1].tointeger());

            local type = NetProps.GetPropType(ent, args[2]);
            local size = max(NetProps.GetPropArraySize(ent, args[2]), 1);
            if (type == null)
                return;

            if (args[3] != "__get")
            {
                switch (type)
                {
                case "bool":
                    local text = replace(args[3], " ", "");
                    local values = split(text, ",");
                    for (local i = 0; i < values.len() && i < size; i++)
                    {
                        if (values[i] != "_")
                            NetProps.SetPropBoolArray(ent, args[2], (bool)values[i].tointeger(), i);
                    }
                    break;
                case "integer":
                    local text = replace(args[3], " ", "");
                    local values = split(text, ",");
                    for (local i = 0; i < values.len() && i < size; i++)
                    {
                        if (values[i] != "_")
                            NetProps.SetPropIntArray(ent, args[2], values[i].tointeger(), i);
                    }
                    break;
                case "float":
                    local text = replace(args[3], " ", "");
                    local values = split(text, ",");
                    for (local i = 0; i < values.len() && i < size; i++)
                    {
                        if (values[i] != "_")
                            NetProps.SetPropFloatArray(ent, args[2], values[i].tofloat(), i);
                    }
                    break;
                case "string":
                    local text = replace(args[3], "', '", "','");
                    local values = splitAt(text, findAllOutsideOf(text, ",", "'", "'"));
                    for (local i = 0; i < values.len() && i < size; i++)
                    {
                        if (values[i] != "_")
                        {
                            local value = values[i];
                            if (value.len() && value[0].tochar() == "'" && value[value.len() - 1].tochar() == "'")
                                value = value.slice(1, value.len() - 1);
                            NetProps.SetPropStringArray(ent, args[2], value, i);
                        }
                    }
                    break;
                //case "table":
                case "Vector":
                    local text = replace(args[3], " ", "");
                    text = replace(text, "vector(", "("); text = replace(text, "v(", "(");
                    text = replace(text, "qangle(", "("); text = replace(text, "q(", "(");
                    local values = splitAt(text, findAllOutsideOf(text, ",", "(", ")"));
                    for (local i = 0; i < values.len() && i < size; i++)
                    {
                        if (values[i] != "_" && values[i].len() && values[i][0].tochar() == "(" && values[i][values[i].len() - 1].tochar() == ")")
                        {
                            local text2 = values[i];
                            text2 = text2.slice(1, text2.len() - 1);
                            local vector = split(text2, ",");
                            if (vector.len() != 3)
                                continue;

                            NetProps.SetPropVectorArray(ent, args[2], Vector(vector[0].tofloat(), vector[1].tofloat(), vector[2].tofloat()), i);
                        }
                    }
                    break;
                case "instance":
                    local text = replace(args[3], " ", "");
                    local values = split(text, ",");
                    for (local i = 0; i < values.len() && i < size; i++)
                    {
                        if (values[i] != "_")
                            NetProps.SetPropEntityArray(ent, args[2], EntIndexToHScript(values[i].tointeger()), i);
                    }
                    break;
                }
            }
            else
            {
                local data = "";
                switch (type)
                {
                case "bool":
                    for (local i = 0; i < size; i++)
                        data += format("%s%s", data != "" ? ", " : "", NetProps.GetPropBoolArray(ent, args[2], i) ? "true" : "false");
                    break;
                case "integer":
                    for (local i = 0; i < size; i++)
                        data += format("%s%d", data != "" ? ", " : "", NetProps.GetPropIntArray(ent, args[2], i));
                    break;
                case "float":
                    for (local i = 0; i < size; i++)
                        data += format("%s%.9g", data != "" ? ", " : "", NetProps.GetPropFloatArray(ent, args[2], i));
                    break;
                case "string":
                    for (local i = 0; i < size; i++)
                        data += format("%s\"%s\"", data != "" ? ", " : "", NetProps.GetPropStringArray(ent, args[2], i));
                    break;
                //case "table":
                case "Vector":
                    for (local i = 0; i < size; i++)
                    {
                        local vec = NetProps.GetPropVectorArray(ent, args[2], i);
                        data += format("%svector(%.9g, %.9g, %.9g)", data != "" ? ", " : "", vec.x, vec.y, vec.z);
                    }
                    break;
                case "instance":
                    for (local i = 0; i < size; i++)
                        data += format("%s%d", data != "" ? ", " : "", NetProps.GetPropEntityArray(ent, args[2], i).entindex());
                    break;
                }
                splitClientPrint(speaker, 3, STATUS + format("  %s (%s, %d) \x01:  %s", args[2], type, size, data));
            }
        }
    }
});
AddCommand({
    "Command": [ "remove_attribute", "removeattribute", "rematr" ],
    "Arguments": [ { "player": "me" }, { "slot": "self" }, { "atr": null } ],
    "Description": [ "Removes the given attribute on a player/weapon" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local ent;
            if (args[1] == "self")
            {
                ent = player;
                ent.RemoveCustomAttribute(args[2]);
            }
            else
            {
                ent = NetProps.GetPropEntityArray(player, "m_hMyWeapons", args[1].tointeger());
                ent.RemoveAttribute(args[2]);
            }
            if (ent != null)
            {
                local toDelete = [];
                foreach (index,dict in TimedAttributes)
                {
                    if (dict.Ent == ent)
                        toDelete.append(index);
                }
                toDelete.reverse();
                foreach (index in toDelete)
                    TimedAttributes.remove(index);
            }
        }
    }
});
AddCommand({
    "Command": [ "remove_condition", "removecondition", "remcond" ],
    "Arguments": [ { "player": "me" }, { "atr": null } ],
    "Description": [ "Removes the given condition on a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            player.RemoveCond(args[1].tointeger());
    }
});
local AtrCondEvents = [];
function OnScriptHook_OnTakeDamage(data)
{
    local victim = data.const_entity;
    local attacker = data.attacker;
    local weapon = data.weapon;

    if (!victim.IsPlayer() || weapon == null) return;

    // probably just loop through instead

    foreach (_,dict in AtrCondEvents)
    {
        if (dict.Player != attacker) continue;

        try
        {
            local player;
            if (dict.Target == "self" || dict.When == "kill")
                player = attacker;
            else if (dict.Target == "victim" && victim.GetTeam() != attacker.GetTeam())
                player = victim;

            local ent;
            if (dict.Slot == "self")
                ent = player;
            else
                ent = NetProps.GetPropEntityArray(player, "m_hMyWeapons", dict.Slot.tointeger());

            local conditionMet = false;
            if (dict.When == "hit")
                conditionMet = true;
            else if (dict.When == "kill" && victim.GetHealth() - (data.damage + data.damage_bonus) <= 0 && victim.GetTeam() != attacker.GetTeam())
                conditionMet = true;
            if (!conditionMet) continue;

            try
            {
                if (dict.Duration == "infinite")
                    player.AddCond(dict.AtrCond.tointeger())
                else
                    player.AddCondEx(dict.AtrCond.tointeger(), dict.Duration.tofloat(), player);
            }
            catch(err)
            {
                if (ent.GetClassname() == "player")
                    ent.AddCustomAttribute(dict.AtrCond, dict.Value.tofloat(), -1);
                else
                    ent.AddAttribute(dict.AtrCond, dict.Value.tofloat(), -1);
                if (dict.Duration != "infinite")
                {
                    TimedAttributes.append({
                        "Ent": ent
                        "Attribute": dict.AtrCond,
                        "Time": Time(),
                        "Duration": dict.Duration.tofloat()
                    });
                }
            }
        }
        catch (err) {}
    }
}
AddCommand({
    "Command": [ "attribute_event", "attributeevent", "atrevent" ],
    "Arguments": [ { "player": "me" }, { "slot": "self" }, { "attribute": null }, { "value": "1" }, { "duration": "infinite" }, { "target": "self" }, { "when": "kill" } ],
    "Description": [ "Gives a player an attribute/condition upon hit/kill", "slot: 'self' - applied to the player, '0' - primary, '1' - secondary, '2' - tertiary, etc (conditions can only be applied to player)", "attribute: '<string>' - for attributes, '<integer>' - for conditions", "target: 'self' - for things to be applied to you, 'victim' - for things to be applied to the victim", "when: 'kill' - to be applied on kill, 'hit' - to be applied on hit" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            AtrCondEvents.append({
                "Player": speaker,
                "AtrCond": args[2].tolower(),
                "Value": args[3].tofloat(),
                "Duration": args[4],
                "Target": args[5].tolower(),
                "Slot": args[1].tolower(),
                "When": args[6].tolower()
            });
        }
    }
});
AddCommand({
    "Command": [ "condition_event", "conditionevent", "condevent" ],
    "Arguments": [ { "player": "me" }, { "condition": null }, { "duration": "infinite" }, { "target": "self" }, { "when": "kill" } ],
    "Description": [ "Gives a player an attribute/condition upon hit/kill", "condition: '<integer>' - for conditions", "target: 'self' - for things to be applied to you, 'victim' - for things to be applied to the victim", "when: 'kill' - to be applied on kill, 'hit' - to be applied on hit" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            AtrCondEvents.append({
                "Player": speaker,
                "AtrCond": args[1].tolower(),
                "Value": 1,
                "Duration": args[2],
                "Target": args[3].tolower(),
                "Slot": "self",
                "When": args[4].tolower()
            });
        }
    }
});
AddCommand({
    "Command": [ "remove_attribute_event", "removeattributeevent", "rematrevent" ],
    "Arguments": [ { "player": "me" }, { "slot": "self" }, { "attribute": "all" } ],
    "Description": [ "Removes a player/weapon event" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local toDelete = [];
            foreach (index,dict in AtrCondEvents)
            {
                if (dict.Ent == ent && (args[1] == "all" || dict.Slot == args[1]) && (args[2] == "all" || dict.AtrCond == args[2]))
                    toDelete.append(index);
            }
            toDelete.reverse();
            foreach (index in toDelete)
                AtrCondEvents.remove(index);
        }
    }
});
AddCommand({
    "Command": [ "remove_condition_event", "removeconditionevent", "remcondevent" ],
    "Arguments": [ { "player": "me" }, { "condition": "all" } ],
    "Description": [ "Removes a player/weapon event" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
        {
            local toDelete = [];
            foreach (index,dict in AtrCondEvents)
            {
                if (dict.Ent == ent && (args[1] == "all" || dict.Slot == args[1]) && (args[2] == "all" || dict.AtrCond == args[2]))
                    toDelete.append(index);
            }
            toDelete.reverse();
            foreach (index in toDelete)
                AtrCondEvents.remove(index)
        }
    }
});
AddCommand({
    "Command": [ "damage_multiplier", "damagemultiplier", "damage_mult", "damagemult" ],
    "Arguments": [ { "team": null }, { "float": "1" } ],
    "Description": [ "Changes how teams recieve damage", "Note: based on recieve, not send" ],
    "Function": function(speaker, args, vars = null)
    {
        if (args[0].tolower().find("blu") != 0)
            Convars.SetValue("tf_damage_multiplier_blue", args[1].tofloat());
        else
            Convars.SetValue("tf_damage_multiplier_red", args[1].tofloat());
    }
});

if ("BotController" in getconsttable())
{
    local pEntity = getconsttable()["BotController"];
    if (pEntity && pEntity.IsValid())
        pEntity.Kill();
}
local controller = Entities.CreateByClassname("bot_controller"); getconsttable()["BotController"] <- controller;
local spawnPosition;
function Bot(position = null)
{
    if (CmdVars.bot_remove.Enabled)
    {
        foreach (player in GetPlayers(null, "bots"))
            player.Kill(); // is there a better way to kick/remove players?
    }
    EntFireByHandle(controller, "CreateBot", "", 0, null, null);
    spawnPosition = position;
}
local spawns = { "1": Vector(440, 0, -16056), "3": Vector(-440, 0, -16056), "4": Vector(0, 440, -16056), "2": Vector(0, -440, -16056), "5": Vector(440, -440, -12280) };
function OnGameEvent_player_spawn(data)
{
    local player = GetPlayerFromUserID(data.userid);
    if (player == null)
        return;

    if (NetProps.GetPropString(player, "m_szNetworkIDString") in Bans)
    {
        player.Kill();
        return;
    }

    if (spawnPosition == null && CmdVars.bot_rampspawn.Enabled && NetProps.GetPropString(player, "m_szNetworkIDString") == "BOT")
    {
        if (CmdVars.bot_forcespawn.Ramp == "0")
            spawnPosition = spawns[RandomInt(1, 4).tostring()];
        else
            spawnPosition = spawns[CmdVars.bot_forcespawn.Ramp];
    }
    if (player in customSpawns)
    {
        player.SetAbsOrigin(customSpawns[player][0]);
        player.SnapEyeAngles(customSpawns[player][1]);
    }
    else if (spawnPosition != null)
        player.SetAbsOrigin(spawnPosition);

    spawnPosition = null;
}
AddCommand({
    "Command": [ "bot" ],
    "Arguments": [ { "class": "original" } ],
    "Description": [ "Spawns a bot" ],
    "Function": function(speaker, args, vars = null)
    {
        local classId = 0;
        try
        {
            classId = args[0].tointeger();
        }
        catch (err) {}
        switch (args[0].tolower())
        {
        case "scout": classId = 1; break;
        case "soldier": classId = 3; break;
        case "pyro": classId = 7; break;
        case "demo":
        case "demoman": classId = 4; break;
        case "heavy": classId = 6; break;
        case "engi":
        case "engineer": classId = 9; break;
        case "medic": classId = 5; break;
        case "sniper": classId = 2; break;
        case "spy": classId = 8; break;
        case "random": classId = 0; break;
        }
        if (args[0].tolower() != "original")
            controller.KeyValueFromInt("bot_class", clamp(classId, 0, 9));

        Bot();
    }
});
AddCommand({
    "Command": [ "bot_remove" ],
    "Arguments": [],
    "Description": [ "Toggles whether or not a bot being spawned clears others" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Bots clear other bots");
        else
            splitClientPrint(speaker, 3, EVENT + "  Bots no longer clear other bots");
    },
    "Variables": { "Enabled": false }
});
AddCommand({
    "Command": [ "bot_temporary", "bot_temp" ],
    "Arguments": [],
    "Description": [ "Toggles whether or not a bot will be removed upon death" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Bots remove on death");
        else
            splitClientPrint(speaker, 3, EVENT + "  Bots no longer remove on death");
    },
    "Variables": { "Enabled": false }
});
AddCommand({
    "Command": [ "bot_name" ],
    "Arguments": [ { "string": "" } ],
    "Description": [ "Sets the name of any new bots" ],
    "Function": function(speaker, args, vars = null)
    {
        controller.KeyValueFromString("bot_name", args[0]);
        splitClientPrint(speaker, 3, EVENT + format("  New bots now have name %s", args[0]));
    }
});
AddCommand({
    "Command": [ "bot_forcespawn", "forcespawn" ],
    "Arguments": [ { "ramp": "0" } ],
    "Description": [ "Switches which ramp bots spawn on", "ramp: '<integer>' - the ramp to spawn on; ramps are numbered; 0 to choose random spawns" ],
    "Function": function(speaker, args, vars = null)
    {
        local number = "0";
        try
        {
            number = clamp(args[0].tointeger(), 0, 5).tostring();
        }
        catch (err) {}
        vars.Ramp = number;
        if (number == "0") number = "random spawns";
        splitClientPrint(speaker, 3, EVENT + format("  Switched bot spawn to %d", number));
    },
    "Variables": { "Ramp": "0" }
});
AddCommand({
    "Command": [ "bot_rampspawn", "bot_spawntp", "bot_ramp" ],
    "Arguments": [],
    "Description": [ "Toggles whether or not bots spawn on ramps" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
            splitClientPrint(speaker, 3, EVENT + "  Bots spawn on ramps");
        else
            splitClientPrint(speaker, 3, EVENT + "  Bots no longer spawn on ramps");
    },
    "Variables": { "Enabled": BotSpawnDefault }
});
AddCommand({
    "Command": [ "bot_mimic" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets whether or not bots mimic" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("bot_mimic", args[0].tointeger());
    }
});
AddCommand({
    "Command": [ "bot_mimic_inverse", "bot_mimicinverse", "bot_inverse" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets whether or not mimic movement is inverse" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("bot_mimic_inverse", args[0].tointeger());
    }
});
AddCommand({
    "Command": [ "bot_mimic_yaw" ],
    "Arguments": [ { "int": "180" } ],
    "Description": [ "Sets the view offset" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("bot_mimic_yaw_offset", args[0].tofloat());
    }
});
AddCommand({
    "Command": [ "net_fakelag", "fakelag", "lag" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets net_fakelag" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("net_fakelag", args[0].tofloat());
    }
});
AddCommand({
    "Command": [ "net_fakejitter", "fakejitter", "jitter" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets net_fakejitter" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("net_fakejitter", args[0].tofloat());
    }
});
AddCommand({
    "Command": [ "net_fakeloss", "fakeloss", "loss" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets net_fakeloss" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("net_fakeloss", args[0].tofloat());
    }
});
AddCommand({
    "Command": [ "walls", "wall" ],
    "Arguments": [],
    "Description": [ "Toggles side walls" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
        {
            EntFire("Wall", "Enable");
            splitClientPrint(speaker, 3, EVENT + "  Walls enabled");
        }
        else
        {
            EntFire("Wall", "Disable");
            splitClientPrint(speaker, 3, EVENT + "  Walls disabled");
        }
    },
    "Variables": { "Enabled": true }
});
AddCommand({
    "Command": [ "fall_boundary", "fallboundary", "fall" ],
    "Arguments": [],
    "Description": [ "Toggles fall boundary" ],
    "Function": function(speaker, args, vars = null)
    {
        vars.Enabled = !vars.Enabled;
        if (vars.Enabled)
        {
            EntFire("FallBoundary", "Enable");
            splitClientPrint(speaker, 3, EVENT + "  Fall boundary enabled");
        }
        else
        {
            EntFire("FallBoundary", "Disable");
            splitClientPrint(speaker, 3, EVENT + "  Fall boundary disabled");
        }
    },
    "Variables": { "Enabled": false }
});
AddCommand({
    "Command": [ "textmsg", "clientprint" ],
    "Arguments": [ { "player": "me" }, { "text": "" } ],
    "Description": [ "Send message to player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (player in GetPlayers(speaker, args[0]))
            splitClientPrint(speaker, 3, args[1]);
    }
});



function GetCommand(text)
{
    return replace(split(text, " ")[0], Prefix, "").tolower();
}
function GetArgs(text, maxArgs = -1)
{
    local args = [];

    local values = splitAt(text, findAllOutsideOf(text, " ", "'", "'"));
    foreach (value in values)
    {
        if (/*value != "" &&*/ (args.len() < maxArgs + 1 || maxArgs == -1))
        {
            if (args.len() < maxArgs && value.len() && value[0].tochar() == "'" && value[value.len() - 1].tochar() == "'")
                value = value.slice(1, value.len() - 1);
            args.append(value);
        }
        else
            args[args.len() - 1] += format(" %s", value);
    }

    args.remove(0); // exclude command

    return args;
}

function OnGameEvent_player_say(data)
{
    if (data.userid == null) return;

    local speaker = GetPlayerFromUserID(data.userid);
    local message = data.text;
    if (message.len() && message[0] == "\x02")
        return; // forced chat, don't run commands

    local commands = split(message, CmdBreak);

    foreach (text in commands)
    {
        text = removeStartingStr(text);
        //text = removeTrailingStr(text);
        if (text.find(Prefix) != 0 || text.len() == 1)
            continue;

        local speakerPermission = GetPlayerPermission(speaker);
        local command = GetCommand(text);

        foreach (entry in Commands)
        {
            foreach (alias in entry.Command)
            {
                if (command == alias)
                    command = entry;
            }
            if (typeof command == "table") break;
        }
        if (typeof command == "string")
        {
            splitClientPrint(speaker, 3, ERROR + "  Invalid command");
            return;
        }
        if (command.Requirement > speakerPermission)
        {
            if (speakerPermission != NO_PERMISSION)
                splitClientPrint(speaker, 3, PERMISSION + "  Insufficient permissions to run this command");
            return;
        }

        local args = GetArgs(text, command.Arguments.len());
        for (local i = 0; i < command.Arguments.len(); i++)
        {
            if (args.len() <= i)
            {
                foreach (_,def in command.Arguments[i])
                {
                    if (def == null)
                    {
                        splitClientPrint(speaker, 3, ERROR + "  Missing argument");
                        return;
                    }
                    args.append(def);
                }
            }
            else if (args[i] == "_")
            {
                foreach (_,def in command.Arguments[i])
                    args[i] = def;
                if (args[i] == null)
                {
                    splitClientPrint(speaker, 3, ERROR + "  Missing argument");
                    return;
                }
            }
        }
        if (command.Command[0] in CmdVars)
            rawcall(command.Function, this, speaker, args, CmdVars[command.Command[0]]); // rawcall needed, dum
        else
            rawcall(command.Function, this, speaker, args);
    }
}

local DeadPlayers = {};
function OnGameEvent_player_death(data)
{
    local player = GetPlayerFromUserID(data.userid);

    if (player.GetHealth() <= 0) // feign
        DeadPlayers[player] <- Time();
}
local MaxAmmos = {};
function OnTimer()
{
    foreach (player,time in DeadPlayers)
    {
        if (Time() > time)
        {
            if (player.IsValid())
            {
                if (CmdVars.bot_temporary.Enabled && NetProps.GetPropString(player, "m_szNetworkIDString") == "BOT") 
                    player.Kill();
                else if (CmdVars.instant_respawn.Enabled)
                    player.ForceRespawn();
            }
            delete DeadPlayers[player];
        }
    }
    foreach (player,_ in customSpawns)
    {
        if (NetProps.GetPropString(player, "m_szNetworkIDString") == "")
            delete customSpawns[player];
    }

    if (CmdVars.constant_regen.Enabled)
    {
        // not using player.Regenerate as that seems somewhat bloated
        local player; while (player = Entities.FindByClassname(player, "player"))
        {
            //if (CmdVars.regen_permission.Requirement > GetPlayerPermission(player))
            //    continue;

            local permission = NO_PERMISSION;
            {   // from GetPlayerPermission as it's erroring upon a map loading it
                local foundRoot = false;
                foreach (uID,permission in Players)
                {
                    if (permission == ROOT_PERMISSION)
                        foundRoot = true;
                }
                if (!foundRoot)
                    permission = GIVEN_PERMISSION;
                else
                {
                    local uID = NetProps.GetPropString(player, "m_szNetworkIDString");
                    if (uID in Players)
                        permission = Players[uID];
                }
            }
            if (CmdVars.regen_permission.Requirement > permission)
                continue;

            if (CmdVars.health_regen.Enabled)
            {
                // health
                player.SetHealth(max(player.GetMaxHealth(), player.GetHealth()));
            }

            if (CmdVars.ammo_regen.Enabled)
            {
                // ammo
                for (local i = 0; i <= NetProps.GetPropArraySize(player, "m_hMyWeapons"); i++)
                {
                    try
                    {
                        local weapon = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i);

                        local iItemDefinitionIndex = NetProps.GetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex");

                        // primary ammo
                        if (iItemDefinitionIndex != 730 && weapon.GetMaxClip1() != -1)
                            weapon.SetClip1(weapon.GetMaxClip1());

                        // reserve/misc ammo
                        local ammoType = weapon.GetPrimaryAmmoType();
                        if (ammoType != -1)
                        {
                            local curAmmo = NetProps.GetPropIntArray(player, "m_iAmmo", ammoType);
                            local maxAmmo = iItemDefinitionIndex in MaxAmmos ? MaxAmmos[iItemDefinitionIndex] : curAmmo;
                            MaxAmmos[iItemDefinitionIndex] <- max(curAmmo, maxAmmo);
                            NetProps.SetPropIntArray(player, "m_iAmmo", MaxAmmos[iItemDefinitionIndex], ammoType);
                        }

                        NetProps.SetPropFloat(weapon, "m_flEnergy", 20);
                    }
                    catch (err) {}
                }
            }

            if (CmdVars.item_regen.Enabled)
            {
                for (local i = 0; i <= NetProps.GetPropArraySize(player, "m_hMyWeapons"); i++)
                {
                    try
                    {
                        local weapon = NetProps.GetPropEntityArray(player, "m_hMyWeapons", i);

                        // spycicle
                        if (NetProps.HasProp(weapon, "m_flKnifeMeltTimestamp"))
                            NetProps.SetPropFloat(weapon, "m_flKnifeMeltTimestamp", 0);

                        // uber
                        if (NetProps.HasProp(weapon, "m_flChargeLevel"))
                            NetProps.SetPropFloat(weapon, "m_flChargeLevel", 1);
                    }
                    catch (err) {}
                }

                // jetpack / gas
                NetProps.SetPropFloatArray(player, "m_Shared.m_flItemChargeMeter", 100, 1);

                // metal
                NetProps.SetPropIntArray(player, "m_iAmmo", 200, 3);

                // cloak
                NetProps.SetPropFloat(player, "m_Shared.m_flCloakMeter", 100);

                // shield
                if (!player.InCond(17 /*TF_COND_SHIELD_CHARGE*/)) // don't spam recharged sound
                    NetProps.SetPropFloat(player, "m_Shared.m_flChargeMeter", 100);

                // banners
                if (!NetProps.GetPropBool(player, "m_Shared.m_bRageDraining")) // don't spam recharged sound
                    NetProps.SetPropFloat(player, "m_Shared.m_flRageMeter", 100);

                // hype / bfb
                if (!player.InCond(36 /*TF_COND_SODAPOPPER_HYPE*/)) // don't spam recharged sound
                    NetProps.SetPropFloat(player, "m_Shared.m_flHypeMeter", 100);
            }
        }
    }

    local toDelete = [];
    foreach (index,dict in TimedAttributes)
    {
        if (dict.Time + dict.Duration < Time())
        {
            if (dict.Ent.GetClassname() == "player")
                dict.Ent.RemoveCustomAttribute(dict.Attribute);
            else
                dict.Ent.RemoveAttribute(dict.Attribute);
            toDelete.append(index);
        }
    }
    toDelete.reverse();
    foreach (index in toDelete)
        TimedAttributes.remove(index);

    toDelete = []
    foreach (index,dict in AtrCondEvents) {
        if (dict.Ent == null)
            toDelete.append(index);
    }
    toDelete.reverse();
    foreach (index in toDelete)
        AtrCondEvents.remove(index);

    foreach (thr,time in sleeps)
    {
        if (Time() > time)
        {
            thr.wakeup();
            delete sleeps[thr];
        }
    }
}

if ("HandlerThink" in getconsttable())
{
    local pEntity = getconsttable()["HandlerThink"];
    if (pEntity && pEntity.IsValid())
        pEntity.Kill();
}
local timer = Entities.CreateByClassname("logic_timer"); getconsttable()["HandlerThink"] <- timer;
timer.KeyValueFromFloat("RefireTime", 0.015);
timer.ValidateScriptScope(); timer.GetScriptScope().OnTimer <- OnTimer;
timer.ConnectOutput("OnTimer", "OnTimer");
EntFireByHandle(timer, "Enable", "", 0, null, null);

local ent; while (ent = Entities.FindByClassname(ent, "trigger_multiple"))
{
    local name = ent.GetName();

    if (name == "BottomTeleport")
    {
        ent.ValidateScriptScope(); ent.GetScriptScope()["On" + name] <- function()
        {
            local origin = activator.GetOrigin();
            activator.SetAbsOrigin(origin + Vector(0, 0, 32170));
        }
        ent.ConnectOutput("OnStartTouch", "On" + name);
    }
    if (name == "TopTeleport")
    {
        ent.ValidateScriptScope(); ent.GetScriptScope()["On" + name] <- function()
        {
            if (activator.GetMoveType() == 8)
            {
                local origin = activator.GetOrigin();
                activator.SetAbsOrigin(origin - Vector(0, 0, 32170));
            }
            else
                activator.SetAbsOrigin(Vector(0, 0, -15823));
        }
        ent.ConnectOutput("OnStartTouch", "On" + name);
    }
}

//ForceEnableUpgrades(2);

__CollectGameEventCallbacks(this);