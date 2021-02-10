/*
-=MONEY-GIVE=- 

Each player can be Money Give to other players.

================================================ 

-=VERSIONS=- 

Releaseed(Time in JP)   Version     comment 
------------------------------------------------ 
2021.02.10              3.00        Converted Amxx to SourceMod 
================================================ 

-=INSTALLATION=- 

Compile and install plugin.
================================================ 

-=USAGE=- 

Client command: say /mg or /mgive or /donate or /money
    - show money give menu.
      select player => select money value. give to other player.

Server Cvars: 
    - amx_mgive                 // enable this plugin. 0 = off, 1 = on.
    - amx_mgive_acs             // Menu access level. 0 = all, 1 = admin only.
    - amx_mgive_max             // A limit of amount of money to have. default $16000
    - amx_mgive_menu_enemies    // menu display in enemies. 0 = off, 1 = on.
    - amx_mgive_menu_bots       // menu display in bots. 0 = off, 1 = on.
    - amx_mgive_bots_action     // The bot gives money to those who have the least money. 0 = off, 1 = on.
                                // (Happens when bot kill someone and exceed your maximum money.)
    - amx_mgive_bank            // Save player money in the bank.
================================================ 

-=SpecialThanks=-
Discord Member for AlliedModders

================================================
*/

#include <sourcemod>
#include <cstrike>
#include <clientprefs>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
    name        = "MONEY-GIVE",
    author      = "Aoi.Kagase",
    description = "Each player can be Money Give to other players.",
    version     = "3.0",
    url         = "https://github.com/AoiKagase"
};

/*=====================================*/
/*  MACRO AREA                           */
/*=====================================*/
#define CHAT_TAG                    "[MONEY-GIVE]"
#define CVAR_TAG                    "sm_mgive"
#define NVAULT_NAME                 "mgive"

// ADMIN LEVEL
#define ADMIN_ACCESSLEVEL           ADMFLAG_CUSTOM1
#define MAX_CVAR_LENGTH             64
#define ROUND_DRAW                  9
#define ROUND_GAME_COMMENCING       15
//====================================================
// ENUM AREA
//====================================================
//
// CVAR SETTINGS
//
enum struct CVARS
{
    ConVar Enable;                  // Plugin Enable.
    ConVar AccessLevel;             // Access level for 0 = ADMIN or 1 = ALL.
    ConVar StartMoney;              // Start Money.
    ConVar MaxMoney;                // Max have money. default:$16000
    ConVar Enemies;                 // Menu display in Enemiy team.
    ConVar BotsMenu;                // Bots in menu. 0 = none, 1 = admin, 2 = all.
    ConVar BotsAction;              // Bots give money action.
    ConVar MoneyList;               // Money list.
    ConVar Bank;                    // Bank system.
}

char CHAT_CMD[][] = {
    "/money",
    "/donate",
    "/mgive",
    "/mg"
};

ArrayList         gMoneyValues;
CVARS             gCvars;
Handle            gCookie;
bool              gCommaning;
//int             g_money[MAXPLAYERS + 1];

public void OnPluginStart()
{
    // CVar settings.
    char cvar[32];
    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_enable");
    gCvars.Enable                 = CreateConVar(cvar, "1");    // 0 = off, 1 = on.
    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_acs");
    gCvars.AccessLevel            = CreateConVar(cvar, "0");    // 0 = all, 1 = admin

    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_max");
    if (!(gCvars.MaxMoney         = FindConVar("mp_maxmoney")))
        gCvars.MaxMoney           = CreateConVar(cvar, "16000");    // Max have money. 

    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_enemies");
    gCvars.Enemies                = CreateConVar(cvar, "0");    // Enemies in menu. 
    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_bots_menu");
    gCvars.BotsMenu               = CreateConVar(cvar, "1");    // Bots in menu. 
    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_bots_action");
    gCvars.BotsAction             = CreateConVar(cvar, "1");    // Bots in action. 

    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_money_list");
    gCvars.MoneyList              = CreateConVar(cvar, "100,500,1000,5000,10000,15000"); 

    FormatEx(cvar, sizeof(cvar), "%s%s", CVAR_TAG, "_bank");
    gCvars.Bank                   = CreateConVar(cvar,"1");    // Bank system.
    gCvars.StartMoney             = FindConVar("mp_startmoney");    // Start money.

    // Bots Action
    HookEvent("player_death", EvBotsAction);
    HookEvent("round_end",    EvRoundEnd);
    HookEvent("player_spawn", EvPlayerSpawn);

    gCookie = FindClientCookie("money-give");
    if (gCookie == INVALID_HANDLE)
        gCookie = RegClientCookie("money-give", "Money-Give Bank System.", CookieAccess_Public);

    InitMoneyList();
}

//====================================================
// Init Money List.
//====================================================
void InitMoneyList()
{
    gMoneyValues = new ArrayList();

    char szCvarMoney[MAX_CVAR_LENGTH];
    gCvars.MoneyList.GetString(szCvarMoney, sizeof(szCvarMoney));
    Format(szCvarMoney, sizeof(szCvarMoney), "%s,", szCvarMoney);

    int i = 0;
    int iPos = 0;
    char szMoney[6];
    while((i = SplitString(szCvarMoney[iPos += i], ",", szMoney, sizeof(szMoney))) != -1)
    {
        gMoneyValues.Push(StringToInt(szMoney));
    }    
}

public void OnClientPutInServer(int client)
{
    if (!gCvars.Bank.IntValue)
        return;

    if (!IsValidClient(client))
        return;

    if (IsFakeClient(client))
        return;

    char szMoney[7];
    GetClientCookie(client, gCookie, szMoney, sizeof(szMoney));
    SetClientMoney(client, StringToInt(szMoney));
}

public void OnClientDisconnect(int client)
{
    if (!gCvars.Bank.IntValue)
        return;

    if (!IsValidClient(client))
        return;

    if (IsFakeClient(client))
        return;

    char szMoney[7];
    int iMoney = GetClientMoney(client);
    IntToString(iMoney, szMoney, sizeof(szMoney));
    SetClientCookie(client, gCookie, szMoney);
}

//====================================================
// Main menu.
//====================================================
public Action MG_PlayerMenu(int client, int args) 
{
    if (!CheckAdmin(client))
        return Plugin_Handled;

    // Create a variable to hold the menu
    Menu menu = new Menu(MG_PlayerMenuHandler);
    menu.SetTitle("Money-Give Menu:");

    // Some variables to hold information about the players
    char szClient[3]; 
    char szMenu[32];

    //Start looping through all players
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidClient(i))
            continue;

        //Save a tempid so we do not re-index
        if (i == client)
            continue;
    
        // display in bots
        if (gCvars.BotsMenu.IntValue == 0)
            if (IsFakeClient(i))
                continue;
        
        // display in enemies.
        if (gCvars.Enemies.IntValue == 0)
            if(GetClientTeam(i) != GetClientTeam(client))
                continue;
         
        //Get the players name and userid as strings
        //We will use the data parameter to send the userid, so we can identify which player was selected in the handler
        FormatEx(szClient, sizeof(szClient), "%d", i);
        FormatEx(szMenu,   sizeof(szMenu),   "%N [$%d]", i, GetClientMoney(i));

        //Add the item for this player
        menu.AddItem(szClient, szMenu);
    }

    //We now have all players in the menu, lets display the menu
    menu.Display(client, 10);
    return Plugin_Handled;
}

//====================================================
// Main menu handler.
//====================================================
public int MG_PlayerMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[32];
            bool found = menu.GetItem(param2, info, sizeof(info));
            if (found)
            {
                int target = StringToInt(info);
                if (IsValidClient(target))
                    MG_MoneyMenu(param1, target);
            }
        }
        case MenuAction_Cancel:
            return;
        case MenuAction_End:
            delete menu;
    }
}

//====================================================
// Sub menu.
//====================================================
public Action MG_MoneyMenu(int client, int player)
{
    Menu menu = new Menu(MG_MoneyMenuHandler);
    menu.SetTitle("Choose Money Value.:");

    int i;
    char szValue[16];
    char szPlayer[3];
    IntToString(player, szPlayer, sizeof(szPlayer));

    int money;
    for(i = 0;i < gMoneyValues.Length; i++)
    {
        money = gMoneyValues.Get(i);
        FormatEx(szValue, sizeof(szValue), "$%d", money);
        menu.AddItem(szPlayer, szValue);
    }
    menu.Display(client, 20);
}

//====================================================
// Sub menu handler.
//====================================================
public int MG_MoneyMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[32];
            bool found = menu.GetItem(param2, info, sizeof(info));
            if (found)
            {
                int target = StringToInt(info);
                int giveMoney = gMoneyValues.Get(param2);
                TransferMoney(param1, target, giveMoney);
            }
        }
        case MenuAction_Cancel:
            if (IsValidClient(param1))
                MG_PlayerMenu(param1, 1);
        case MenuAction_End:
            delete menu;
    }

    return;
}

//====================================================
// Chat command.
//====================================================
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if(!gCvars.Enable.IntValue)
        return Plugin_Continue;

    if (!CheckAdmin(client))
        return Plugin_Continue;

    char said[32];
    char target[MAX_NAME_LENGTH];
    char money[7];

    int arg = -1;
    arg  = BreakString(sArgs, said, sizeof(said));
    if (arg > -1)
    arg += BreakString(sArgs[arg], target, sizeof(target));
    if (arg > -1)
    arg += BreakString(sArgs[arg], money, sizeof(money));

    for(int i = 0; i < sizeof(CHAT_CMD); i++)
    {
        if (strcmp(said, CHAT_CMD[i]) == 0)
        {
            TrimString(target);
            TrimString(money);
            if (strcmp(target, "") == 0 && strcmp(money, "") == 0)
                MG_PlayerMenu(client, 1);
            else
                CmdMoneyTransfer(client, target, StringToInt(money));
            return Plugin_Handled;
        }
    }


    if (StrContains(said, "give") != -1 
    ||  StrContains(said, "money")!= -1
    ||  StrContains(said, "mg")   != -1)
    {
        PrintToChat(client, "\4%s \1/mg or /mgive is show money give menu", CHAT_TAG);
        return Plugin_Handled;
    }
    return Plugin_Handled;
}

//====================================================
// Check Logic.
//====================================================
bool CheckAdmin(int client)
{
    if (gCvars.AccessLevel.IntValue)
        return view_as<bool>(GetUserFlagBits(client) & ADMIN_ACCESSLEVEL);

    return true;
}

int GetClientMoney(int client)
{
    return GetEntProp(client, Prop_Send, "m_iAccount");
}

void SetClientMoney(int client, int money)
{
    SetEntProp(client, Prop_Send, "m_iAccount", money);
}

//====================================================
// Bots Action.
//====================================================
public void EvBotsAction(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (IsFakeClient(attacker))
    {    
        int maxMoney = gCvars.MaxMoney.IntValue;
        int tgtMoney = maxMoney;
        int botMoney = GetClientMoney(attacker);

        int target;
        int temp;
        const int botGive = 500;

        if (botMoney >= maxMoney)
        {
            // get minimun money have player.
            for (int i = 1; i <= MaxClients; i++)
            {
                if (!IsValidClient(i))
                    continue;

                if (IsFakeClient(i))
                    continue;

                if (GetClientTeam(i) != GetClientTeam(attacker))
                    continue;

                temp = GetClientMoney(i);
                if (tgtMoney > temp)
                {
                    tgtMoney = temp;
                    target     = i;
                }
            }
            if (IsValidClient(target))
                TransferMoney(attacker, target, botGive, true);
        }
    }
}

public void EvRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int reasonId = event.GetInt("reason");
	if (reasonId == ROUND_GAME_COMMENCING || reasonId == ROUND_DRAW)
		gCommaning = true;
	else
		gCommaning = false;
}

public void EvPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (gCommaning)
	{
        char szMoney[7];
        GetClientCookie(client, gCookie, szMoney, sizeof(szMoney));
        SetClientMoney(client, StringToInt(szMoney));
	}
}

//====================================================
// Chat Command.
//====================================================
void CmdMoneyTransfer(int client, char target[MAX_NAME_LENGTH], int money)
{
    // check param[] is none.
    if (!target[0])
    {
        PrintToChat(client, "%s Usage: '\4/mg^1 <target> <money>'", CHAT_TAG);
        return;
    }
 
    int player = FindTarget(client, target, false, false);
    if (IsValidClient(player))
    {
        if (!gCvars.Enemies.IntValue)
            if (GetClientTeam(player) != GetClientTeam(client))
                return;
        TransferMoney(client, player, money);
    }
} 

//====================================================
// Transfer Money.
//====================================================
void TransferMoney(int from, int to, int value, bool fromBot = false)
{
    int mMoney = gCvars.MaxMoney.IntValue;            // MAX
    int fMoney = GetClientMoney(from);                // From
    int tMoney = GetClientMoney(to);                // To

    // don't enough!
    if (!fromBot)
    if (fMoney < value) 
    {
        PrintToChat(from, "\3%s You don't have enough money to gaving!", CHAT_TAG);
        return;
    }

    // his max have money.
    if (mMoney < tMoney + value)
    {
        fMoney -= (mMoney - tMoney);
        tMoney  = mMoney;
    }
    // give.
    else
    {
        fMoney -= value;
        tMoney += value;
    }

    if (IsClientInGame(from))
        SetClientMoney(from,fMoney);
    if (IsClientInGame(to))
        SetClientMoney(to,  tMoney);

    if (!fromBot)
        PrintToChat(from, "\4%s \1$%d was give to \3\"%N\".", CHAT_TAG, value, to);

    PrintToChat(to, "\4%s \1$%d was give from \3\"%N\".",     CHAT_TAG, value, from);
}

bool IsValidClient(int client, bool replaycheck = true)
{
    if(client <= 0 || client > MaxClients)
        return false;

    if(!IsClientInGame(client))
        return false;

//  if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
//      return false;

    if(replaycheck)
    {
        if(IsClientSourceTV(client) || IsClientReplay(client)) 
            return false;
    }
    return true;
} 