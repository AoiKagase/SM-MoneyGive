/*
-=MONEY-GIVE=- 

Each player can be Money Give to other players.

================================================ 

-=VERSIONS=- 

Releaseed(Time in JP)	Version 	comment 
------------------------------------------------ 
2005.01.29		1.02		main release 
2005.01.29		1.03		Rename
2005.03.11		1.04		Can donate to the immunity.
							Bot was stopped in the reverse.
2006.03.15		1.05		Any bugfix
2020.03.20		2.00		Rewriten New menu system.
							change cvars and cmds.
================================================ 

-=INSTALLATION=- 

Compile and install plugin. (configs/plugins.ini) 
================================================ 

-=USAGE=- 

Client command: say /mg or /mgive or /donate or /money
	- show money give menu.
	  select player => select money value. give to other player.

Server Cvars: 
	- amx_mgive		 			// enable this plugin. 0 = off, 1 = on.
	- amx_mgive_acs 			// Menu access level. 0 = all, 1 = admin only.
	- amx_mgive_max 			// A limit of amount of money to have. default $16000
	- amx_mgive_menu_enemies	// menu display in enemies. 0 = off, 1 = on.
	- amx_mgive_menu_bots		// menu display in bots. 0 = off, 1 = on.
	- amx_mgive_bots_action		// The bot gives money to those who have the least money. 0 = off, 1 = on.
								// (Happens when bot kill someone and exceed your maximum money.)
	- amx_mgive_bank			// Save player money in the bank.
================================================ 

-=SpecialThanks=-
Idea	Mr.Kaseijin
Tester	Mr.Kaseijin
		orutiga
		justice

================================================
*/


#define REAPI_SUPPORT

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
public Plugin myinfo = 
{
	name 		= "MONEY-GIVE",
	author 		= "Aoi.Kagase",
	description = "Each player can be Money Give to other players.",
	version 	= "3.0",
	url 		= "https://github.com/AoiKagase"
};

/*=====================================*/
/*  MACRO AREA					       */
/*=====================================*/
#define CHAT_TAG 					"[MONEY-GIVE]"
#define CVAR_TAG					"sm_mgive"
#define NVAULT_NAME					"mgive"

// ADMIN LEVEL
#define ADMIN_ACCESSLEVEL			ADMFLAG_CUSTOM1
#define MAX_CVAR_LENGTH				64

//====================================================
// ENUM AREA
//====================================================
//
// CVAR SETTINGS
//
enum struct CVAR_SETTING
{
	ConVar CVAR_ENABLE; 		// Plugin Enable.
	ConVar CVAR_ACCESS_LEVEL; 	// Access level for 0 = ADMIN or 1 = ALL.
	ConVar CVAR_MAX_MONEY; 		// Max have money. default:$16000
	ConVar CVAR_ENEMIES; 		// Menu display in Enemiy team.
	ConVar CVAR_BOTS_MENU; 		// Bots in menu. 0 = none, 1 = admin, 2 = all.
	ConVar CVAR_BOTS_ACTION; 	// Bots give money action.
	ConVar CVAR_MONEY_LIST; 	// Money list.
	ConVar CVAR_BANK; 			// Bank system.
	ConVar CVAR_START_MONEY;
}

#pragma semicolon 1

char CHAT_CMD[][] 		= {
	"/money",
	"/donate",
	"/mgive",
	"/mg"
};

ArrayList 		gMoneyValues;
//Handle 			g_nv_handle;
CVAR_SETTING 	g_cvar;
//int 			g_money[MAXPLAYERS + 1];
int 			g_iAccount;

public void OnPluginStart()
{
	g_iAccount = FindSendPropInfo("CCSPlayer", "m_iAccount");
	if (g_iAccount == -1)
	{
		SetFailState("[SMX] Money-Give - Failed to find offset for m_iAccount!");
	}
	
	RegConsoleCmd("say", 		say_mg);
	RegConsoleCmd("say_team", 	say_mg);

	// CVar settings.
	char cvar[32];
	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_enable");
	g_cvar.CVAR_ENABLE 			= CreateConVar(cvar, "1");	// 0 = off, 1 = on.
	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_acs");
	g_cvar.CVAR_ACCESS_LEVEL 	= CreateConVar(cvar, "0");	// 0 = all, 1 = admin

	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_max");
	if (!(g_cvar.CVAR_MAX_MONEY = FindConVar("mp_maxmoney")))
		g_cvar.CVAR_MAX_MONEY 	= CreateConVar(cvar, "16000");	// Max have money. 

	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_enemies");
	g_cvar.CVAR_ENEMIES			= CreateConVar(cvar, "0");	// Enemies in menu. 
	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_bots_menu");
	g_cvar.CVAR_BOTS_MENU		= CreateConVar(cvar, "1");	// Bots in menu. 
	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_bots_action");
	g_cvar.CVAR_BOTS_ACTION		= CreateConVar(cvar, "1");	// Bots in action. 

	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_money_list");
	g_cvar.CVAR_MONEY_LIST		= CreateConVar(cvar, "100,500,1000,5000,10000,15000"); 

	FormatEx(cvar, sizeof(cvar) - 1, "%s%s", CVAR_TAG, "_bank");
	g_cvar.CVAR_BANK			= CreateConVar(cvar,"1");	// Bank system.
	g_cvar.CVAR_START_MONEY		= FindConVar("mp_startmoney");	// Start money.

	// Bots Action
	// register_event_ex	("DeathMsg", "bots_action", RegisterEvent_Global);
	HookEvent("player_death", BotsAction, EventHookMode_Post);

	InitMoneyList();
}

//====================================================
// Destruction.
//====================================================
public void OnPluginEnd() 
{ 
	gMoneyValues.Clear();
	delete gMoneyValues;
	// ArrayDestroy(gMoneyValues);
	// nvault_close(g_nv_handle);
}

//====================================================
// Init Money List.
//====================================================
InitMoneyList()
{
	//gMoneyValues = ArrayCreate(1);
	gMoneyValues = new ArrayList();
	char cvar_money[MAX_CVAR_LENGTH];
	GetConVarString(g_cvar.CVAR_MONEY_LIST, cvar_money, sizeof(cvar_money) - 1);
	Format(cvar_money, sizeof(cvar_money) - 1, "%s,", cvar_money);

	int i = 0;
	int iPos = 0;
	char szMoney[6];
	while((i = SplitString(cvar_money[iPos += i], ",", szMoney, sizeof(szMoney) - 1)) != -1)
	{
		gMoneyValues.Push(StringToInt(szMoney));
	}	
}

// void OnClientAuthorized(int client, const char[] auth)
// {
// 	if (!GetConVarInt(g_cvar[CVAR_BANK]))
// 		return Plugin_Continue;

// 	if (IsFakeClient(id))
// 		return Plugin_Continue;

// 	// new authid[MAX_AUTHID_LENGTH], temp[7], timestamp;

// 	// if (nvault_lookup(g_nv_handle, authid, temp, charsmax(temp), timestamp))
// 	// {
// 	// 	g_money[id] = str_to_num(temp);
// 	// 	g_money[id] = g_money[id] > 0 ? g_money[id] : g_cvar[CVAR_START_MONEY];
// 	// }

// }

public OnClientPutInServer(client)
{
}

// public client_putinserver(id)
// {
// 	if (!g_cvar[CVAR_BANK])
// 		return PLUGIN_CONTINUE;

// 	if (is_user_bot(id))
// 		return PLUGIN_CONTINUE;

// 	if (is_user_connected(id))
// 		cs_set_user_money(id, g_money[id], 0);

// 	return PLUGIN_CONTINUE;
// }

// public client_disconnected(id)
// {
// 	if (is_user_bot(id))
// 		return PLUGIN_CONTINUE;

// 	if (!g_cvar[CVAR_BANK])
// 		return PLUGIN_CONTINUE;

// 	new authid[MAX_AUTHID_LENGTH];
// 	get_user_authid(id, authid, charsmax(authid));

// 	if(pev_valid(id))
// 		nvault_set(g_nv_handle, authid, fmt("%d", get_pdata_int(id, OFFSET_MONEY)));

// 	return PLUGIN_CONTINUE;
// }

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
	char szUserId[32]; 
	char szMenu[32];

	//Start looping through all players
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		//Save a tempid so we do not re-index
		if (i == client)
			continue;
	
		// display in bots
		if (GetConVarInt(g_cvar.CVAR_BOTS_MENU) == 0)
			if (IsFakeClient(i))
				continue;
		
		// display in enemies.
		if (GetConVarInt(g_cvar.CVAR_ENEMIES) == 0)
			if(GetClientTeam(i) != GetClientTeam(client))
				continue;
		 
		//Get the players name and userid as strings
		//We will use the data parameter to send the userid, so we can identify which player was selected in the handler
		FormatEx(szUserId,	sizeof(szUserId) - 1, "%d", i);
		FormatEx(szMenu,	sizeof(szMenu) - 1, "%-16N [$%6d]", i, GetClientMoney(i));

		//Add the item for this player
		menu.AddItem(szUserId, szMenu);
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
			bool found = menu.GetItem(param2, info, sizeof(info) - 1);
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
public Action MG_MoneyMenu(client, player)
{
	Menu menu = new Menu(MG_MoneyMenuHandler);
	menu.SetTitle("Choose Money Value.:");

	int i;
	char szValue[16];
	char szPlayer[3];
	IntToString(player, szPlayer, sizeof(szPlayer) - 1);

	new money;
	for(i = 0;i < gMoneyValues.Length; i++)
	{
		money = gMoneyValues.Get(i);
		FormatEx(szValue, sizeof(szValue) - 1, "$%d", money);
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
			bool found = menu.GetItem(param2, info, sizeof(info) - 1);
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
public Action say_mg(int client, int args)
{
	if(!GetConVarInt(g_cvar.CVAR_ENABLE))
		return Plugin_Continue;

	if (!CheckAdmin(client))
		return Plugin_Continue;

	char szMessages[32];
	char said[32];
	char target[MAX_NAME_LENGTH];
	char money[7];

	GetCmdArg(1, szMessages, sizeof(szMessages)  - 1);
	int arg = -1;
	arg  = BreakString(szMessages, said, sizeof(said) - 1);
	if (arg > -1)
	arg += BreakString(szMessages[arg], target, sizeof(target) - 1);
	if (arg > -1)
	arg += BreakString(szMessages[arg], money, sizeof(money) - 1);

	for(new i = 0; i < sizeof(CHAT_CMD); i++)
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
	||	StrContains(said, "money")!= -1
	||	StrContains(said, "mg")   != -1)
	{
		PrintToChat(client, "\4%s \1/mg or /mgive is show money give menu", CHAT_TAG);
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

//====================================================
// Check Logic.
//====================================================
bool CheckAdmin(client)
{
	if (GetConVarInt(g_cvar.CVAR_ACCESS_LEVEL))
		return bool:(GetUserFlagBits(client) & ADMIN_ACCESSLEVEL);

	return true;
}

int GetClientMoney(client)
{
	return GetEntData(client, g_iAccount);
}

void SetClientMoney(client, money)
{
	SetEntData(client, g_iAccount, money);
}

//====================================================
// Bots Action.
//====================================================
public void BotsAction(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = event.GetBool("attacker");
	if (IsValidClient(attacker) && IsFakeClient(attacker))
	{	
		int maxMoney = GetConVarInt(g_cvar.CVAR_MAX_MONEY);
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
					target	 = i;
				}
			}
			if (IsValidClient(target))
				TransferMoney(attacker, target, botGive, true);
		}
	}
}

//====================================================
// Chat Command.
//====================================================
CmdMoneyTransfer(int client, char target[MAX_NAME_LENGTH], int money)
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
		if (!GetConVarInt(g_cvar.CVAR_ENEMIES))
			if (GetClientTeam(player) != GetClientTeam(client))
				return;
		TransferMoney(client, player, money);
	}

	return;
} 

//====================================================
// Transfer Money.
//====================================================
TransferMoney(from, to, int value, bool fromBot = false)
{
	int mMoney	= GetConVarInt(g_cvar.CVAR_MAX_MONEY);	// MAX
	int fMoney 	= GetClientMoney(from);				// From
	int tMoney 	= GetClientMoney(to);				// To

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
		SetClientMoney(to,	tMoney);

	if (!fromBot)
		PrintToChat(from, "\4%s \1$%d was give to \3\"%N\".", CHAT_TAG, value, to);

	PrintToChat(to, "\4%s \1$%d was give from \3\"%N\".", 	CHAT_TAG, value, from);

	return;
}

bool IsValidClient(client, bool:replaycheck = true)
{
	if(client <= 0 || client > MaxClients)
		return false;

	if(!IsClientInGame(client))
		return false;

//	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
//		return false;

	if(replaycheck)
	{
		if(IsClientSourceTV(client) || IsClientReplay(client)) 
			return false;
	}
	return true;
} 