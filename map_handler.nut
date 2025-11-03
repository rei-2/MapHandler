local Prefix = "!";
//local HiddenPrefix = ":"; // currently unused, not sure of a way to filter/hide chat messages
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

local BotSpawnDefault = false;
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
local function clamp(value, min, max)
{
    if (min > max) throw("Minimum larger than maximum");
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
local function tobool(str)
{
    switch (str.tolower())
    {
    case "t":
    case "tr":
    case "tru":
    case "true": return true;
    }
    try
    {
        return str.tointeger() ? true : false;
    }
    catch (err)
    {
        return false;
    }
}
local sleeps = {};
local function sleep(seconds, thr)
{
    sleeps[thr] <- Time() + seconds;
    suspend("sleep");
}

local function findAll(text, pattern, from = 0, to = 0)
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
local function findAllOutsideOf(text, pattern, start, end, from = 0, to = 0)
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
local function replace(text, pattern, replacement, from = 0, to = 0)
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
local function splitAt(text, positions)
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
local function multString(text, number)
{
    local str = "";
    for (local i = 0; i < number; i++)
        str += text;
    return str;
}
local function removeStartingStr(text, char = " ")
{
    while (text.len() && text[0].tochar() == char)
        text = text.slice(1, text.len());
    return text;
}
local function removeTrailingStr(text, char = " ")
{
    while (text.len() && text[text.len() - 1].tochar() == char)
        text = text.slice(0, text.len() - 1);
    return text;
}
local function splitClientPrint(speaker, destination, message)
{
    while (message.len())
    {
        ClientPrint(speaker, destination, message.slice(0, min(MESSAGE_MAX_LENGTH, message.len())));
        message = message.slice(min(MESSAGE_MAX_LENGTH, message.len()), message.len());
    }
}
local function GetPlayerName(player)
{
    return NetProps.GetPropString(player, "m_szNetname");
}
local function GetPlayerID(player)
{
    return NetProps.GetPropString(player, "m_szNetworkIDString");
}



ClearGameEventCallbacks();



local Commands = [];
local CmdVars = {};
local function AddCommand(commandInfo)
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
            if (GetPlayerID(ent) != "BOT")
                players.append(ent);
        }
        return players;
    },
    "bots": function(speaker)
    {
        local players = [];
        for (local ent; ent = Entities.FindByClassname(ent, "player");)
        {
            if (GetPlayerID(ent) == "BOT")
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
            if (GetPlayerID(ent) == text.toupper())
                return [ ent ];
        }
        return [];
    },

    "entities": function(speaker)
    {
        local entities = [];
        for (local ent = Entities.First(); ent; ent = Entities.Next(ent))
            entities.append(ent);
        return entities;
    },
    "e:_": function(speaker, text)
    {
        for (local ent; ent = Entities.FindByClassname(ent, text);)
            return [ ent ];
        return [];
    },
    "es:_": function(speaker, text)
    {
        local entities = [];
        for (local ent; ent = Entities.FindByClassname(ent, text);)
            entities.append(ent);
        return entities;
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

local TargetPlayers = 1 << 0;
local TargetOther = 1 << 1;
local function GetTargets(speaker, text, flags = TargetPlayers)
{
    local list = split(text.tolower(), ",");
    local add = [], sub = [];

    foreach (plrStr in list)
    {
        local to = add;
        if (plrStr.find("+") == 0)
            plrStr = replace(plrStr, "+", "");
        else if (plrStr.find("-") == 0)
            to = sub, plrStr = replace(plrStr, "-", "");

        local caseFound = false;
        foreach (str,func in specialCases)
        {
            local flag = TargetPlayers;
            switch (str)
            {
            case "entities":
            case "e:_":
            case "es:_":
            case "!picker": flag = TargetOther;
            }
            if (!(flags & flag))
                continue;

            if (str.find("_") != null && plrStr.find(replace(str, "_", "")) == 0)
            {
                try
                {
                    foreach (target in func(speaker, plrStr.slice(replace(str, "_", "").len(), plrStr.len())))
                    {
                        if (to.find(target) == null)
                            to.append(target);
                    }
                    caseFound = true;
                }
                catch (err) {}
            }
            if (plrStr == str && !caseFound)
            {
                caseFound = true;
                foreach (target in func(speaker))
                {
                    if (to.find(target) == null)
                        to.append(target);
                }
            }
        }
        if (!caseFound)
        {
            local ent; while (ent = Entities.FindByClassname(ent, "player"))
            {
                if (GetPlayerName(ent).tolower().find(plrStr) == 0 && to.find(ent) == null)
                    to.append(ent);
            }
        }
    }

    local targets = [];
    foreach (target in add)
    {
        if (sub.find(target) == null)
            targets.append(target);
    }
    return targets;
}
local function GetPlayerPermission(player, fallback = NO_PERMISSION)
{
    local uID = GetPlayerID(player);
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
        foreach (target in GetTargets(speaker, args[0]))
            splitClientPrint(speaker, 3, INFORMATION + format("  %s: %s", GetPlayerName(target), GetPlayerID(target)));
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
                Players[GetPlayerID(speaker)] <- ROOT_PERMISSION;
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local uID = GetPlayerID(target);
            if (!(uID in Players) || Players[uID] == NO_PERMISSION)
            {
                Players[uID] <- GIVEN_PERMISSION;
                splitClientPrint(speaker, 3, PERMISSION + format("  Gave command permissions to %s", GetPlayerName(target)));
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local uID = GetPlayerID(target);
            if (uID in Players && GetPlayerPermission(target) < ROOT_PERMISSION)
            {
                delete Players[uID];
                splitClientPrint(speaker, 3, PERMISSION + format("  Removed command permissions from %s", GetPlayerName(target)));
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
        foreach (target in GetTargets(speaker, args[0]))
            splitClientPrint(speaker, 3, PERMISSION + format("  Permission of %s is %d", GetPlayerName(target), GetPlayerPermission(target)));
    }
});
AddCommand({
    "Command": [ "respawn", "res" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Respawn a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            target.ForceRespawn();
    }
});
AddCommand({
    "Command": [ "refresh", "re" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Respawn a player, while retaining position, viewangles, and some other data" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local origin = target.GetOrigin();
            local velocity = target.GetVelocity();
            local angles = target.EyeAngles();
            local moveType = target.GetMoveType();
            target.ForceRespawn();
            target.SetAbsOrigin(origin);
            target.SetVelocity(velocity);
            target.SnapEyeAngles(angles);
            target.SetMoveType(moveType, 0);
        }
    }
});
AddCommand({
    "Command": [ "reset" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Respawn a player, while retaining position and viewangles" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local origin = target.GetOrigin();
            local velocity = target.GetVelocity();
            local angles = target.EyeAngles();
            target.ForceRespawn();
            target.SetAbsOrigin(origin);
            target.SetVelocity(velocity);
            target.SnapEyeAngles(angles);
        }
    }
});
AddCommand({
    "Command": [ "stun" ],
    "Arguments": [ { "player": "me" }, { "duration": "1" }, { "speed reduction": "0.5" }, { "flags": "1" } ],
    "Description": [ "Stuns a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            target.StunPlayer(args[1].tofloat(), args[2].tofloat(), args[3].tointeger(), null);
    }
});
AddCommand({
    "Command": [ "kill" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Kill a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            //NetProps.SetPropInt(target, "m_lifeState", 1);
            target.TakeDamage(target.GetHealth() + 1, 0, null);
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local playerPermission = GetPlayerPermission(target);
            if (speakerPermission <= playerPermission)
            {
                splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to kick %s", GetPlayerName(target)));
                continue;
            }

            splitClientPrint(speaker, 3, EVENT + format("  Kicked %s", GetPlayerName(target)));
            target.Kill(); // is there a better way to kick/remove players?
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local playerPermission = GetPlayerPermission(target);
            if (speakerPermission <= playerPermission)
            {
                splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to ban %s", GetPlayerName(target)));
                continue;
            }

            Bans[GetPlayerID(target)] <- { "Name": GetPlayerName(target), "Requirement": speakerPermission };
            splitClientPrint(speaker, 3, EVENT + format("  Banned %s", GetPlayerName(target)));
            target.Kill();
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
        foreach (target in GetTargets(speaker, args[0]))
            Say(target, format("\x02%s", args[1]), false); // use \x02 to prevent unwanted usage of commands
    }
});
AddCommand({
    "Command": [ "team_chat", "teamchat" ],
    "Arguments": [ { "player": null, "message": null } ],
    "Description": [ "Force a player to team chat" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            Say(target, format("\x02%s", args[1]), true);
    }
});
AddCommand({
    "Command": [ "clearchat" ],
    "Arguments": [ { "count": "248" } ],
    "Description": [ "Clears chat with newlines" ],
    "Function": function(speaker, args, vars = null)
    {
        local count = args[0].tointeger();

        local str = "";
        for (local i = 0; i < count; i++)
        {
            if (!(str.len() % MESSAGE_MAX_LENGTH))
                str += " ";
            str += "\n";
        }
        splitClientPrint(null, 3, str);
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
        foreach (target in GetTargets(speaker, args[0]))
            NetProps.SetPropFloat(target, "m_flMaxspeed", args[1].tofloat());
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            if (tobool(args[1]))
                target.SetHealth(target.GetMaxHealth());
            else
                target.SetHealth(max(target.GetMaxHealth(), target.GetHealth()));
        }
    }
});
AddCommand({
    "Command": [ "health" ],
    "Arguments": [ { "player": "me" }, { "value": "__get" } ],
    "Description": [ "Gives players a given health" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            if (args[1] != "__get")
                target.SetHealth(args[1].tointeger());
            else
                splitClientPrint(speaker, 3, STATUS + format("  Health of %s is %.9g", GetPlayerName(target), target.GetHealth()));
        }
    }
});
AddCommand({
    "Command": [ "maxhealth" ],
    "Arguments": [ { "player": "me" }, { "value": "__get" } ],
    "Description": [ "Sets players' max health" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            if (args[1] != "__get")
            {
                local health = target.GetMaxHealth() - target.GetCustomAttribute("max health additive bonus", 0);
                target.AddCustomAttribute("max health additive bonus", args[1].tointeger() - health, -1);
            }
            else
                splitClientPrint(speaker, 3, STATUS + format("  Max health of %s is %.9g", GetPlayerName(target), target.GetMaxHealth()));
        }
    }
});
if (AllowGiveWeapon)
{
    AddCommand({
        "Command": [ "give_weapon", "giveweapon", "give" ],
        "Arguments": [ { "player": "me" }, { "weapon": null } ],
        "Description": [ "Gives a specified weapon to a player" ],
        "Function": function(speaker, args, vars = null)
        {
            foreach (target in GetTargets(speaker, args[0]))
                target.GiveWeapon(args[1]);
        }
    });
}
AddCommand({
    "Command": [ "noclip" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Toggles a player's noclip" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            if (target.GetMoveType() != 8)
                target.SetMoveType(8, 0);
            else
                target.SetMoveType(2, 0);
        }
    }
});
AddCommand({
    "Command": [ "setmovetype", "movetype" ],
    "Arguments": [ { "player": "me" }, { "movetype": "2" }, { "movecollide": "0" } ],
    "Description": [ "Sets a player's movetype", "See https://developer.valvesoftware.com/wiki/Team_Fortress_2/Scripting/Script_Functions/Constants for values for EMoveType and EMoveCollide" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            target.SetMoveType(args[1].tointeger(), args[2].tointeger());
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
                local target = GetTargets(speaker, args[1])[0];
                pos = target.GetOrigin();
                if (tobool(args[2]))
                    offset += Vector(0, 0, target.GetBoundingMaxs().z + 1);
            }
        }

        foreach (target in GetTargets(speaker, args[0]))
        {
            target.SetAbsOrigin(pos + offset);
            if (tobool(args[2]))
                offset += Vector(0, 0, target.GetBoundingMaxs().z + 1);
        }
    }
});
AddCommand({
    "Command": [ "to" ],
    "Arguments": [ { "to": null }, { "offset": "false" } ],
    "Description": [ "Teleports to another player", "from: '<player>'", "to: '<player>', '__cursor' / '__bounds' / '__plane' / '__point' - your aim position, with varying bounds (__plane and __point may get stuck), 'vector(x, y, z)' - some position" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (entry in Commands)
        {
            if (entry.Command[0] == "teleport")
            {
                entry.Function(speaker, [ "me" args[0], args[1] ]);
                break;
            }
        }
    }
});
AddCommand({
    "Command": [ "getposition", "getpos", "gp" ],
    "Arguments": [ { "player": "me" }, { "precise": "false" } ],
    "Description": [ "Gets the position of a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local vec = target.GetOrigin();
            if (tobool(args[1]))
                splitClientPrint(speaker, 3, STATUS + format("  Position of %s is vector(%.9g, %.9g, %.9g)", GetPlayerName(target), vec.x, vec.y, vec.z));
            else
                splitClientPrint(speaker, 3, STATUS + format("  Position of %s is vector(%.0f, %.0f, %.0f)", GetPlayerName(target), vec.x, vec.y, vec.z));
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
        foreach (target in GetTargets(speaker, args[0]))
            target.SetVelocity(value);
    }
});
AddCommand({
    "Command": [ "getvelocity", "getvel", "gv" ],
    "Arguments": [ { "player": "me" }, { "precise": "false" } ],
    "Description": [ "Gets the velocity of a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local vec = target.GetVelocity();
            if (tobool(args[1]))
                splitClientPrint(speaker, 3, STATUS + format("  Velocity of %s is vector(%.9g, %.9g, %.9g)", GetPlayerName(target), vec.x, vec.y, vec.z));
            else
                splitClientPrint(speaker, 3, STATUS + format("  Velocity of %s is vector(%.0f, %.0f, %.0f)", GetPlayerName(target), vec.x, vec.y, vec.z));
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
        foreach (target in GetTargets(speaker, args[0]))
            target.SnapEyeAngles(value);
    }
});
AddCommand({
    "Command": [ "getangles", "getang", "ga" ],
    "Arguments": [ { "player": "me" }, { "precise": "false" } ],
    "Description": [ "Gets the eye angles of a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local ang = target.EyeAngles();
            if (tobool(args[1]))
                splitClientPrint(speaker, 3, STATUS + format("  Eye angles of %s is qangle(%.9g, %.9g, %.9g)", GetPlayerName(target), ang.x, ang.y, ang.z));
            else
                splitClientPrint(speaker, 3, STATUS + format("  Eye angles of %s is qangle(%.0f, %.0f, %.0f)", GetPlayerName(target), ang.x, ang.y, ang.z));
        }
    }
});
AddCommand({
    "Command": [ "thirdperson", "third" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Forces third person" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            target.SetForcedTauntCam(1);
    }
});
AddCommand({
    "Command": [ "firstperson", "first" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Forces first person" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            target.SetForcedTauntCam(0);
    }
})
AddCommand({
    "Command": [ "taunt" ],
    "Arguments": [ { "player": "me" },{ "taunt": null } ],
    "Description": [ "Forces a player to taunt", "Taunt IDs: https://github.com/Bradasparky/tf_taunt_tastic/blob/main/addons/sourcemod/configs/tf_taunt_tastic.cfg" /*, "Taunt IDs: https://wiki.alliedmods.net/Team_fortress_2_item_definition_indexes#Taunt_Items", "Taunt IDs: https://steamcommunity.com/app/440/discussions/0/2765630416816834092/"*/ ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local weapon = Entities.CreateByClassname("tf_weapon_bat");
            local activeWeapon = target.GetActiveWeapon();

            target.StopTaunt(true); // both are needed to fully clear the taunt
            target.RemoveCond(7);

            weapon.DispatchSpawn();
            NetProps.SetPropInt(weapon, "m_AttributeManager.m_Item.m_iItemDefinitionIndex", args[1].tointeger());
            NetProps.SetPropBool(weapon, "m_AttributeManager.m_Item.m_bInitialized", true);
            NetProps.SetPropBool(weapon, "m_bForcePurgeFixedupStrings", true);
            NetProps.SetPropEntity(target, "m_hActiveWeapon", weapon);
            NetProps.SetPropInt(target, "m_iFOV", 0); // fix sniper rifles
            target.HandleTauntCommand(0);
            NetProps.SetPropEntity(target, "m_hActiveWeapon", activeWeapon);
            weapon.Kill();
        }
    }
});
AddCommand({
    "Command": [ "fov" ],
    "Arguments": [ { "player": "me" }, { "value": 90 } ],
    "Description": [ "Forces first person" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            NetProps.SetPropInt(target, "m_iFOV", args[1].tointeger());
    }
});
AddCommand({
    "Command": [ "team" ],
    "Arguments": [ { "player": "me" }, { "team": "__swap" }, { "respawn": "false" } ],
    "Description": [ "Sets a player's team", "Team: Numbers or 'BLU' / 'RED'; '2' - RED, '3' - BLU" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local newTeam = 0;
            if (args[1] == "__swap")
            {
                switch (target.GetTeam())
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

            target.ForceChangeTeam(newTeam, true);
            NetProps.SetPropInt(target, "m_iTeamNum", newTeam);
            local cosmetic = null; while (cosmetic = Entities.FindByClassname(cosmetic, "tf_wearable"))
            {
                if (cosmetic.GetOwner() == target)
                    cosmetic.SetTeam(newTeam);
            }

            if (tobool(args[2]))
                target.ForceRespawn();
        }
    }
});
AddCommand({
    "Command": [ "class" ],
    "Arguments": [ { "player": "me" }, { "team": "random" }, { "mode": "refresh" } ],
    "Description": [ "Sets a player's class" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
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

            target.SetPlayerClass(classId);
            NetProps.SetPropInt(target, "m_Shared.m_iDesiredPlayerClass", classId);

            switch (args[2].tolower())
            {
            case "respawn":
                target.ForceRespawn();
                break;
            case "refresh":
                local origin = target.GetOrigin();
                local velocity = target.GetVelocity();
                local angles = target.EyeAngles();
                local moveType = target.GetMoveType();
                target.ForceRespawn();
                target.SetAbsOrigin(origin);
                target.SetVelocity(velocity);
                target.SnapEyeAngles(angles);
                target.SetMoveType(moveType, 0);
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
                bValue = tobool(args[0]) ? true : false;
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
AddCommand({
    "Command": [ "instant_requirement", "instant_permission" ],
    "Arguments": [ { "permission": null } ],
    "Description": [ "Sets permission required to have instant respawn be used" ],
    "Function": function(speaker, args, vars = null)
    {
        local requirement = args[0].tointeger();
        local permission = GetPlayerPermission(speaker);
        if (permission < vars.Requirement || permission < requirement)
        {
            splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to set instant respawn requirement from %d to %d", vars.Requirement, requirement));
            return;
        }

        vars.Requirement = requirement;
        splitClientPrint(speaker, 3, EVENT + format("  Instant respawn requirement set to %d", requirement));
    },
    "Variables": { "Requirement": NO_PERMISSION }
});
local customSpawns = {}
AddCommand({
    "Command": [ "custom_spawn", "customspawn", "set_spawn", "setspawn" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Creates a custom respawn point for a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local pos = target.GetOrigin() + Vector(0, 0, 1);
            local ang = target.EyeAngles();
            customSpawns[target] <- [ pos, ang ];
            splitClientPrint(speaker, 3, EVENT + format("  Gave %s a custom spawn at vector(%.9g, %.9g, %.9g)", GetPlayerName(target), pos.x, pos.y, pos.z));
        }
    }
});
AddCommand({
    "Command": [ "remove_custom_spawn", "removecustomspawn", "reset_spawn", "resetspawn" ],
    "Arguments": [ { "player": "me" } ],
    "Description": [ "Removes a custom respawn point for a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            if (target in customSpawns) delete customSpawns[target];
            splitClientPrint(speaker, 3, EVENT + format("  Removed %s's custom spawn"), GetPlayerName(target));
        }
    }
});
AddCommand({
    "Command": [ "constant_regen", "constantregen", "regen" ],
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
    "Command": [ "regen_requirement", "regen_permission" ],
    "Arguments": [ { "permission": null } ],
    "Description": [ "Sets permission required to have regen be used" ],
    "Function": function(speaker, args, vars = null)
    {
        local requirement = args[0].tointeger();
        local permission = GetPlayerPermission(speaker);
        if (permission < vars.Requirement || permission < requirement)
        {
            splitClientPrint(speaker, 3, PERMISSION + format("  Insufficient permissions to set regen requirement from %d to %d", vars.Requirement, requirement));
            return;
        }

        vars.Requirement = requirement;
        splitClientPrint(speaker, 3, EVENT + format("  Regen requirement set to %d", requirement));
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

        foreach (target in GetTargets(speaker, args[3]))
        {
            local dist = (target.GetOrigin() + Vector(0, 0, 42) - trace.pos).Length();
            if (dist > args[0].tofloat())
                continue;

            local _trace = {
                "start": trace.pos,
                "end": target.GetOrigin() + Vector(0, 0, 42),
                "ignore": target
            };
            if (!TraceLineEx(_trace))
                throw("TraceLineEx error. ");
            if (_trace.hit)
                continue;

            local _dir = (target.GetOrigin() + Vector(0, 0, 42) - trace.pos); dist /= args[0].tofloat(); _dir.Norm();
            printl(_dir * (1 - (dist * args[2].tofloat())) * args[1].tofloat());
            target.SetAbsOrigin(target.GetOrigin() + Vector(0, 0, 19));
            target.ApplyAbsVelocityImpulse(_dir * (1 - (dist * args[2].tofloat())) * args[1].tofloat());
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local ent = target;
            if (args[1] != "self")
                ent = NetProps.GetPropEntityArray(ent, "m_hMyWeapons", args[1].tointeger());
            if (!ent)
                continue;

            if (ent.IsPlayer()) // rework to use IsPlayer, do ent stuff beforehand, do for all instances of this
            {
                if (args[3] != "__get")
                    ent.AddCustomAttribute(args[2], args[3].tofloat(), -1);
                else
                    splitClientPrint(speaker, 3, STATUS + format("  Attribute %s is %.9g", args[2], ent.GetCustomAttribute(args[2], -2147483647)));
            }
            else
            {
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            if (args[2] == "infinite")
                target.AddCond(args[1].tointeger())
            else
                target.AddCondEx(args[1].tointeger(), args[2].tofloat(), target)
        }
    }
});
AddCommand({
    "Command": [ "netvar", "netprop", "net" ],
    "Arguments": [ { "target": "me" }, { "slot": "self" }, { "netvar": null }, { "value": "__get" } ],
    "Description": [ "Sets or gets the netvar of the target", "slot: 'self' - applied to you, '0' - primary, '1' - secondary, '2' - tertiary, etc", "netprop: '<string>' - list at https://jackz.me/netprops/tf2/netprops / https://sigwiki.potato.tf/index.php/Entity_Properties" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0], TargetPlayers | TargetOther))
        {
            local ent = target;
            if (args[1] != "self")
                ent = NetProps.GetPropEntityArray(ent, "m_hMyWeapons", args[1].tointeger());
            if (!ent)
                continue;

            local type = NetProps.GetPropType(ent, args[2]);
            local size = max(NetProps.GetPropArraySize(ent, args[2]), 1);
            if (type == null)
                continue;

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
                            NetProps.SetPropBoolArray(ent, args[2], tobool(values[i]), i);
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
    "Command": [ "fire" ],
    "Arguments": [ { "target": "me" }, { "slot": "self" }, { "input": null }, { "param": "" } ],
    "Description": [ "Fires event on the target" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0], TargetPlayers | TargetOther))
        {
            local ent = target;
            if (args[1] != "self")
                ent = NetProps.GetPropEntityArray(ent, "m_hMyWeapons", args[1].tointeger());
            if (!ent)
                continue;

            ent.AcceptInput(args[2], args[3], null, null);
        }
    }
});
AddCommand({
    "Command": [ "remove_attribute", "removeattribute", "rematr" ],
    "Arguments": [ { "player": "me" }, { "slot": "self" }, { "atr": null } ],
    "Description": [ "Removes the given attribute on a player/weapon" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
        {
            local ent = target;
            if (args[1] != "self")
                ent = NetProps.GetPropEntityArray(ent, "m_hMyWeapons", args[1].tointeger());
            if (!ent)
                continue;

            if (ent.IsPlayer())
                ent.RemoveCustomAttribute(args[2]);
            else
                ent.RemoveAttribute(args[2]);

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
});
AddCommand({
    "Command": [ "remove_condition", "removecondition", "remcond" ],
    "Arguments": [ { "player": "me" }, { "atr": null } ],
    "Description": [ "Removes the given condition on a player" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            target.RemoveCond(args[1].tointeger());
    }
});
local AtrCondEvents = [];
function OnScriptHook_OnTakeDamage(data)
{
    local victim = data.const_entity;
    local attacker = data.attacker;
    local weapon = data.weapon;

    if (!victim.IsPlayer() || !weapon)
        return;

    // probably just loop through instead

    foreach (_,dict in AtrCondEvents)
    {
        if (dict.Player != attacker)
            continue;

        try
        {
            local target;
            if (dict.Target == "self" || dict.When == "kill")
                target = attacker;
            else if (dict.Target == "victim" && victim.GetTeam() != attacker.GetTeam())
                target = victim;

            local ent = target;
            if (dict.Slot != "self")
                ent = NetProps.GetPropEntityArray(ent, "m_hMyWeapons", dict.Slot.tointeger());

            local conditionMet = false;
            if (dict.When == "hit")
                conditionMet = true;
            else if (dict.When == "kill" && victim.GetHealth() - (data.damage + data.damage_bonus) <= 0 && victim.GetTeam() != attacker.GetTeam())
                conditionMet = true;
            if (!conditionMet)
                continue;

            try
            {
                if (dict.Duration == "infinite")
                    target.AddCond(dict.AtrCond.tointeger())
                else
                    target.AddCondEx(dict.AtrCond.tointeger(), dict.Duration.tofloat(), target);
            }
            catch(err)
            {
                if (ent.IsPlayer())
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            AtrCondEvents.append({
                "Player": target,
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            AtrCondEvents.append({
                "Player": target,
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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local ent = target;
            if (args[1] != "self")
                ent = NetProps.GetPropEntityArray(ent, "m_hMyWeapons", args[1].tointeger());
            if (!ent)
                continue;

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
        foreach (target in GetTargets(speaker, args[0]))
        {
            local ent = target;

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
local function Bot(position = null)
{
    if (CmdVars.bot_remove.Enabled)
    {
        foreach (target in GetTargets(null, "bots"))
            target.Kill(); // is there a better way to kick/remove players?
    }
    EntFireByHandle(controller, "CreateBot", "", 0, null, null);
    spawnPosition = position;
}
local spawns = [ Vector(440, 0, -16056), Vector(-440, 0, -16056), Vector(0, 440, -16056), Vector(0, -440, -16056), Vector(440, -440, -12280) ];
function OnGameEvent_player_spawn(data)
{
    local target = GetPlayerFromUserID(data.userid);
    if (!target)
        return;

    if (GetPlayerID(target) in Bans)
    {
        target.Kill();
        return;
    }

    if (spawnPosition == null && CmdVars.bot_spawntp.Enabled && GetPlayerID(target) == "BOT")
    {
        if (CmdVars.bot_spawntp.Spawn == 0)
            spawnPosition = spawns[RandomInt(0, spawns.len() - 1)];
        else
            spawnPosition = spawns[CmdVars.bot_spawntp.Spawn - 1];
    }
    if (target in customSpawns)
    {
        target.SetAbsOrigin(customSpawns[target][0]);
        target.SnapEyeAngles(customSpawns[target][1]);
    }
    else if (spawnPosition != null)
        target.SetAbsOrigin(spawnPosition);

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
    "Command": [ "bot_spawntp", "bot_spawns", "bot_spawn" ],
    "Arguments": [{ "spawn": "__toggle" }],
    "Description": [ "Toggles whether or not bots have custom spawns", "spawn: '<integer>' - the spawn to use, 0 to choose random spawns" ],
    "Function": function(speaker, args, vars = null)
    {
        if (args[0] == "__toggle")
        {
            vars.Enabled = !vars.Enabled;
            if (vars.Enabled)
                splitClientPrint(speaker, 3, EVENT + "  Bot spawns enabled");
            else
                splitClientPrint(speaker, 3, EVENT + "  Bot spawns disabled");
        }
        else
        {
            local number = 0;
            try
            {
                number = clamp(args[0].tointeger(), 0, spawns.len());
            }
            catch (err) {}
            vars.Spawn = number;

            if (number == 0)
                number = "random spawns";
            else
                number = number.tostring();
            splitClientPrint(speaker, 3, EVENT + format("  Switched bot spawn to %s", number));
        }
    },
    "Variables": { "Enabled": BotSpawnDefault, "Spawn": 0 }
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
    "Command": [ "bot_mimic_inverse", "bot_inverse" ],
    "Arguments": [ { "int": "0" } ],
    "Description": [ "Sets whether or not mimic movement is inverse" ],
    "Function": function(speaker, args, vars = null)
    {
        Convars.SetValue("bot_mimic_inverse", args[0].tointeger());
    }
});
AddCommand({
    "Command": [ "bot_mimic_yaw_offset", "bot_mimic_yaw", "bot_yaw" ],
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
        foreach (target in GetTargets(speaker, args[0]))
            splitClientPrint(target, 3, args[1]);
    }
});
AddCommand({
    "Command": [ "textmsgtype", "clientprinttype" ],
    "Arguments": [ { "player": "me" }, { "type": "3" }, { "text": "" } ],
    "Description": [ "Send message to player", "type: 1: HUD_PRINTNOTIFY, 2: HUD_PRINTCONSOLE, 3: HUD_PRINTTALK, 4: HUD_PRINTCENTER" ],
    "Function": function(speaker, args, vars = null)
    {
        foreach (target in GetTargets(speaker, args[0]))
            splitClientPrint(target, args[1].tointeger(), args[2]);
    }
});
AddCommand({
    "Command": [ "printtargets", "printtarget", "pt" ],
    "Arguments": [ { "target": "me" } ],
    "Description": [ "Prints classnames of targets" ],
    "Function": function(speaker, args, vars = null)
    {
        local i = 0;
        foreach (target in GetTargets(speaker, args[0], TargetPlayers | TargetOther))
            splitClientPrint(speaker, 3, STATUS + format("  %i \x01:  %s", i++, target.GetClassname()));
    }
});



local function GetCommand(text)
{
    return replace(split(text, " ")[0], Prefix, "").tolower();
}
local function GetArgs(text, maxArgs = -1)
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
    if (data.userid == null)
        return;

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
        command.Function(speaker, args, command.Command[0] in CmdVars ? CmdVars[command.Command[0]] : null);
    }
}

local DeadPlayers = {};
function OnGameEvent_player_death(data)
{
    local target = GetPlayerFromUserID(data.userid);
    if (target == null)
        return;

    if (target.GetHealth() <= 0) // feign
        DeadPlayers[target] <- Time();
}
local MaxAmmos = {};
local function OnTimer()
{
    foreach (player,time in DeadPlayers)
    {
        if (Time() > time)
        {
            if (player.IsValid())
            {
                if (CmdVars.bot_temporary.Enabled && GetPlayerID(player) == "BOT") 
                    player.Kill();
                else if (CmdVars.instant_respawn.Enabled)
                {
                    if (CmdVars.instant_requirement.Requirement <= GetPlayerPermission(player))
                        player.ForceRespawn();
                }
            }
            delete DeadPlayers[player];
        }
    }
    foreach (player,_ in customSpawns)
    {
        if (GetPlayerID(player) == "")
            delete customSpawns[player];
    }

    if (CmdVars.constant_regen.Enabled)
    {
        // not using player.Regenerate as that seems somewhat bloated
        local player; while (player = Entities.FindByClassname(player, "player"))
        {
            if (CmdVars.regen_requirement.Requirement > GetPlayerPermission(player))
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

                        // carbine
                        if (NetProps.HasProp(weapon, "m_flMinicritCharge") && !player.InCond(19 /*TF_COND_ENERGY_BUFF*/)) // allow expiration
                            NetProps.SetPropFloat(weapon, "m_flMinicritCharge", 100);
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
            if (dict.Ent.IsPlayer())
                dict.Ent.RemoveCustomAttribute(dict.Attribute);
            else
                dict.Ent.RemoveAttribute(dict.Attribute);
            toDelete.append(index);
        }
    }
    toDelete.reverse();
    foreach (index in toDelete)
        TimedAttributes.remove(index);

    toDelete = [];
    foreach (index,dict in AtrCondEvents)
    {
        if (!dict.Ent)
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